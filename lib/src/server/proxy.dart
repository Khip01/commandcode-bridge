import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/account.dart';
import '../models/models_db.dart';
import '../services/log_store.dart';

class ProxyServer {
  HttpServer? _server;
  final AccountStore accountStore;
  final ConfigStore configStore;
  bool _running = false;
  String _currentModel = 'deepseek/deepseek-v4-flash';
  int _modelVersion = 0;

  bool get isRunning => _running;
  String get currentModel => _currentModel;
  int get modelVersion => _modelVersion;

  ProxyServer({required this.accountStore, required this.configStore});

  Future<void> start() async {
    if (_running) return;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        configStore.config.serverPort,
      );
      _running = true;
      LogStore.success('Proxy server started on port ${configStore.config.serverPort}');
      _server!.listen(_handleRequest);
    } catch (e) {
      LogStore.error('Failed to start server: $e');
      rethrow;
    }
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _server?.close(force: true);
    _server = null;
    LogStore.info('Proxy server stopped');
  }

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    final method = request.method;

    try {
      if (path == '/v1/chat/completions' && method == 'POST') {
        _handleChatCompletions(request);
      } else if (path == '/v1/models' && method == 'GET') {
        _handleModels(request);
      } else if (path == '/v1/health' && method == 'GET') {
        _handleHealth(request);
      } else if (path == '/v1/token' && method == 'GET') {
        _handleToken(request);
      } else if (path == '/v1/info' && method == 'GET') {
        _handleInfo(request);
      } else {
        _sendJson(request.response, 404, {'error': 'Not found', 'path': path});
      }
    } catch (e) {
      LogStore.error('Request error: $e');
      _sendJson(request.response, 500, {'error': 'Internal server error'});
    }
  }

  Future<void> _handleChatCompletions(HttpRequest request) async {
    final acc = accountStore.account;
    if (acc == null) {
      _sendJson(request.response, 401, {
        'error': 'Not authenticated. Run cmd login first.',
      });
      return;
    }

    try {
      final bytes = await request.toList();
      final body = utf8.decode(bytes.expand((b) => b).toList());
      final openaiReq = jsonDecode(body) as Map<String, dynamic>;
      final normalized = _normalizeRequest(openaiReq);

      final model = openaiReq['model'] as String? ?? 'deepseek/deepseek-v4-flash';
      final stream = openaiReq['stream'] as bool? ?? false;
      final maxTokens = (openaiReq['max_tokens'] as num? ??
              openaiReq['max_completion_tokens'] as num?)
          ?.toInt() ??
          64000;
      final temperature = openaiReq['temperature'] as num?;
      final tools = _toWireTools(openaiReq['tools']);

      _currentModel = model;
      _modelVersion++;

      if (stream) {
        await _proxyStreaming(
          request.response,
          acc,
          model,
          normalized.messages,
          tools,
          maxTokens,
          temperature,
          normalized.system,
        );
      } else {
        await _proxyNonStreaming(
          request.response,
          acc,
          model,
          normalized.messages,
          tools,
          maxTokens,
          temperature,
          normalized.system,
        );
      }
    } catch (e) {
      LogStore.error('Chat completion error: $e');
      _sendJson(request.response, 500, {'error': 'Internal error: $e'});
    }
  }

  Future<void> _proxyStreaming(
    HttpResponse response,
    AppAccount acc,
    String model,
    List<Map<String, dynamic>> wireMessages,
    List<Map<String, dynamic>> wireTools,
    int maxTokens,
    num? temperature,
    String? system,
  ) async {
    final stopwatch = Stopwatch()..start();

    final body = {
      'params': {
        'model': model,
        'messages': wireMessages,
        if (wireTools.isNotEmpty) 'tools': wireTools,
        'stream': true,
        'max_tokens': maxTokens,
        if (temperature != null) 'temperature': temperature.toDouble(),
        if (system != null) 'system': system,
      },
      'config': {
        'workingDir': '/tmp',
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'environment': 'production',
        'structure': <String>[],
        'isGitRepo': false,
        'currentBranch': '',
        'mainBranch': '',
        'gitStatus': '',
        'recentCommits': <String>[],
      },
      'memory': null,
      'taste': null,
      'skills': null,
      'permissionMode': 'standard',
    };

    final client = HttpClient();
    try {
      final upstreamReq = await client.postUrl(
        Uri.parse('${configStore.config.apiBaseUrl}/alpha/generate'),
      );

      upstreamReq.headers.set('Authorization', 'Bearer ${acc.apiKey}');
      upstreamReq.headers.contentType = ContentType.json;
      upstreamReq.headers.set('User-Agent', 'cli');
      upstreamReq.headers.set('x-command-code-version', configStore.config.cliVersion);
      upstreamReq.headers.set('x-cli-environment', 'production');

      upstreamReq.add(utf8.encode(jsonEncode(body)));

      final upstreamRes = await upstreamReq.close();

      response.statusCode = upstreamRes.statusCode;
      response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      response.headers.set('Cache-Control', 'no-cache');
      response.headers.set('Connection', 'keep-alive');

      if (upstreamRes.statusCode == 200) {
        String finishReason = 'stop';
        int inputTokens = 0;
        int outputTokens = 0;
        String leftover = '';
        bool sentAssistantRole = false;
        final toolCalls = <Map<String, dynamic>>[];

        await for (final chunk in utf8.decoder.bind(upstreamRes)) {
          final parts = (leftover + chunk).split('\n');
          leftover = parts.removeLast();

          for (final line in parts) {
            if (line.trim().isEmpty) continue;
            try {
              final event = jsonDecode(line) as Map<String, dynamic>;
              final type = event['type'] as String?;

              switch (type) {
                case 'text-delta':
                  _sendSSE(response, {
                    'id': event['id'],
                    'object': 'chat.completion.chunk',
                    'choices': [
                      {
                        'delta': {
                          if (!sentAssistantRole) 'role': 'assistant',
                          'content': event['text'] ?? '',
                        },
                        'index': 0,
                      }
                    ],
                  });
                  sentAssistantRole = true;
                  break;

                case 'reasoning-delta':
                  _sendSSE(response, {
                    'id': event['id'],
                    'object': 'chat.completion.chunk',
                    'choices': [
                      {
                        'delta': {
                          if (!sentAssistantRole) 'role': 'assistant',
                          'reasoning_content': event['text'] ?? '',
                        },
                        'index': 0,
                      }
                    ],
                  });
                  sentAssistantRole = true;
                  break;

                case 'tool-call':
                  final toolCall = _toOpenAiToolCall(
                    event,
                    index: toolCalls.length,
                    includeIndex: true,
                  );
                  toolCalls.add(toolCall);
                  _sendSSE(response, {
                    'id': event['id'],
                    'object': 'chat.completion.chunk',
                    'choices': [
                      {
                        'delta': {
                          if (!sentAssistantRole) 'role': 'assistant',
                          'tool_calls': [toolCall],
                        },
                        'index': 0,
                      }
                    ],
                  });
                  sentAssistantRole = true;
                  break;

                case 'finish':
                  finishReason = event['finishReason'] as String? ?? 'stop';
                  final usage = event['totalUsage'] as Map<String, dynamic>?;
                  if (usage != null) {
                    inputTokens = (usage['inputTokens'] as num?)?.toInt() ?? 0;
                    outputTokens = (usage['outputTokens'] as num?)?.toInt() ?? 0;
                  }
                  break;

                case 'error':
                  final err = event['error'] as Map<String, dynamic>?;
                  final msg = err?['message'] as String? ?? 'Unknown error';
                  _sendSSE(response, {
                    'error': {'message': msg, 'type': 'api_error'},
                  });
                  LogStore.error('Chat upstream error ($model): $msg');
                  break;
              }
            } catch (_) {}
          }
        }

        if (toolCalls.isNotEmpty && finishReason == 'stop') {
          finishReason = 'tool_calls';
        }

        _sendSSE(response, {
          'id': 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
          'object': 'chat.completion.chunk',
          'choices': [
            {
              'delta': {},
              'finish_reason': _mapFinishReason(finishReason),
              'index': 0,
            }
          ],
          'usage': {
            'prompt_tokens': inputTokens,
            'completion_tokens': outputTokens,
            'total_tokens': inputTokens + outputTokens,
          },
        });

        response.write('data: [DONE]\n\n');
        LogStore.success(
          'Chat ok ($model, ${stopwatch.elapsed.inMilliseconds}ms, in=$inputTokens, out=$outputTokens${toolCalls.isNotEmpty ? ', tool_calls=${toolCalls.length}' : ''})',
        );
      } else {
        final errBytes = await upstreamRes.toList();
        final errBody = utf8.decode(errBytes.expand((b) => b).toList());
        final msg = _extractUpstreamErrorMessage(errBody);
        _sendSSE(response, {
          'error': {'message': msg, 'type': 'upstream_error'},
        });
        LogStore.error('Chat rejected ($model): $msg');
      }
    } catch (e) {
      LogStore.error('Streaming proxy error ($model): $e');
      _sendSSE(response, {
        'error': {'message': 'Proxy error: $e', 'type': 'proxy_error'},
      });
    } finally {
      client.close();
      await response.flush();
      await response.close();
    }
  }

  Future<void> _proxyNonStreaming(
    HttpResponse response,
    AppAccount acc,
    String model,
    List<Map<String, dynamic>> wireMessages,
    List<Map<String, dynamic>> wireTools,
    int maxTokens,
    num? temperature,
    String? system,
  ) async {
    final stopwatch = Stopwatch()..start();

    final body = {
      'params': {
        'model': model,
        'messages': wireMessages,
        if (wireTools.isNotEmpty) 'tools': wireTools,
        'stream': true,
        'max_tokens': maxTokens,
        if (temperature != null) 'temperature': temperature.toDouble(),
        if (system != null) 'system': system,
      },
      'config': {
        'workingDir': '/tmp',
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'environment': 'production',
        'structure': <String>[],
        'isGitRepo': false,
        'currentBranch': '',
        'mainBranch': '',
        'gitStatus': '',
        'recentCommits': <String>[],
      },
      'memory': null,
      'taste': null,
      'skills': null,
      'permissionMode': 'standard',
    };

    final client = HttpClient();
    try {
      final upstreamReq = await client.postUrl(
        Uri.parse('${configStore.config.apiBaseUrl}/alpha/generate'),
      );

      upstreamReq.headers.set('Authorization', 'Bearer ${acc.apiKey}');
      upstreamReq.headers.contentType = ContentType.json;
      upstreamReq.headers.set('User-Agent', 'cli');
      upstreamReq.headers.set('x-command-code-version', configStore.config.cliVersion);
      upstreamReq.headers.set('x-cli-environment', 'production');

      upstreamReq.add(utf8.encode(jsonEncode(body)));

      final upstreamRes = await upstreamReq.close();

      if (upstreamRes.statusCode != 200) {
        final errBytes = await upstreamRes.toList();
        final errBody = utf8.decode(errBytes.expand((b) => b).toList());
        final msg = _extractUpstreamErrorMessage(errBody);
        _sendJson(response, upstreamRes.statusCode, {
          'error': {'message': msg, 'type': 'upstream_error'},
        });
        LogStore.error('Chat rejected ($model): $msg');
        return;
      }

      String content = '';
      String? reasoning;
      String finishReason = 'stop';
      int inputTokens = 0;
      int outputTokens = 0;
      final toolCalls = <Map<String, dynamic>>[];
      String leftover = '';

      await for (final raw in upstreamRes) {
        final chunk = utf8.decode(raw);
        final parts = (leftover + chunk).split('\n');
        leftover = parts.removeLast();

        for (final line in parts) {
          if (line.trim().isEmpty) continue;
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            switch (event['type'] as String?) {
              case 'text-delta':
                content += (event['text'] as String? ?? '');
                break;
              case 'reasoning-delta':
                reasoning = (reasoning ?? '') + (event['text'] as String? ?? '');
                break;
              case 'tool-call':
                toolCalls.add(_toOpenAiToolCall(event));
                break;
              case 'finish':
                finishReason = event['finishReason'] as String? ?? 'stop';
                final usage = event['totalUsage'] as Map<String, dynamic>?;
                if (usage != null) {
                  inputTokens = (usage['inputTokens'] as num?)?.toInt() ?? 0;
                  outputTokens = (usage['outputTokens'] as num?)?.toInt() ?? 0;
                }
                break;
            }
          } catch (_) {}
        }
      }

      if (toolCalls.isNotEmpty && finishReason == 'stop') {
        finishReason = 'tool_calls';
      }

      final choice = <String, dynamic>{
        'index': 0,
        'message': {
          'role': 'assistant',
          'content': content,
          if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
        },
        'finish_reason': _mapFinishReason(finishReason),
      };

      if (reasoning != null && reasoning.isNotEmpty) {
        (choice['message'] as Map<String, dynamic>)['reasoning_content'] = reasoning;
      }

      _sendJson(response, 200, {
        'id': 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
        'object': 'chat.completion',
        'model': model,
        'choices': [choice],
        'usage': {
          'prompt_tokens': inputTokens,
          'completion_tokens': outputTokens,
          'total_tokens': inputTokens + outputTokens,
        },
      });

      LogStore.success(
        'Chat ok ($model, ${stopwatch.elapsed.inMilliseconds}ms, in=$inputTokens, out=$outputTokens${toolCalls.isNotEmpty ? ', tool_calls=${toolCalls.length}' : ''})',
      );
    } catch (e) {
      LogStore.error('Non-streaming proxy error ($model): $e');
      _sendJson(response, 500, {'error': 'Proxy error: $e'});
    } finally {
      client.close();
    }
  }

  _NormalizedRequest _normalizeRequest(Map<String, dynamic> request) {
    final messages = request['messages'] as List<dynamic>? ?? const [];
    final normalized = <Map<String, dynamic>>[];
    final systemParts = <String>[];

    for (final raw in messages) {
      if (raw is! Map) continue;
      final role = raw['role'] as String? ?? 'user';

      if (role == 'system') {
        final text = _extractTextContent(raw['content']);
        if (text.isNotEmpty) systemParts.add(text);
        continue;
      }

      if (role == 'tool') {
        final toolResult = _toWireToolMessage(raw);
        if (toolResult != null) normalized.add(toolResult);
        continue;
      }

      final message = _toWireMessage(raw);
      if (message != null) normalized.add(message);
    }

    final directSystem = request['system'];
    if (directSystem is String && directSystem.trim().isNotEmpty) {
      systemParts.add(directSystem.trim());
    }

    return _NormalizedRequest(
      messages: normalized,
      system: systemParts.isEmpty ? null : systemParts.join('\n\n'),
    );
  }

  Map<String, dynamic>? _toWireMessage(Map raw) {
    final role = raw['role'] as String? ?? 'user';
    final wireRole = role == 'assistant' ? 'assistant' : 'user';
    final content = _toWireContent(
      raw['content'],
      allowToolCalls: role == 'assistant',
      toolCalls: role == 'assistant' ? raw['tool_calls'] ?? raw['toolCalls'] : null,
      functionCall: role == 'assistant' ? raw['function_call'] ?? raw['functionCall'] : null,
    );
    if (content.isEmpty && role != 'assistant') return null;
    if (content.isEmpty && role == 'assistant') return {'role': wireRole, 'content': const <Map<String, dynamic>>[]};
    return {'role': wireRole, 'content': content};
  }

  Map<String, dynamic>? _toWireToolMessage(Map raw) {
    final toolCallId = raw['tool_call_id'] as String? ?? raw['toolCallId'] as String?;
    if (toolCallId == null || toolCallId.isEmpty) return null;

    final outputText = _extractTextContent(raw['content']);
    return {
      'role': 'tool',
      'content': [
        {
          'type': 'tool-result',
          'toolCallId': toolCallId,
          'toolName': raw['name'] as String? ?? '',
          'output': {
            'type': 'text',
            'value': outputText,
          },
        }
      ],
    };
  }

  List<Map<String, dynamic>> _toWireTools(dynamic tools) {
    if (tools is! List) return const [];

    final result = <Map<String, dynamic>>[];
    for (final raw in tools) {
      if (raw is! Map) continue;
      if ((raw['type'] as String?) != 'function') continue;

      final function = raw['function'] as Map<String, dynamic>? ?? const {};
      final name = function['name'] as String?;
      if (name == null || name.isEmpty) continue;

      result.add({
        'name': name,
        'description': function['description'] as String? ?? '',
        'input_schema': _toJsonSchema(function['parameters']),
      });
    }

    return result;
  }

  Map<String, dynamic> _toJsonSchema(dynamic schema) {
    if (schema is Map<String, dynamic>) return schema;
    if (schema is Map) return Map<String, dynamic>.from(schema);
    return {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
      'additionalProperties': true,
    };
  }

  List<Map<String, dynamic>> _toWireContent(
    dynamic content, {
    required bool allowToolCalls,
    dynamic toolCalls,
    dynamic functionCall,
  }) {
    final wireContent = <Map<String, dynamic>>[];

    if (content is String) {
      if (content.isNotEmpty) {
        wireContent.add({'type': 'text', 'text': content});
      }
    } else if (content is List) {
      for (final part in content) {
        if (part is! Map) continue;
        final type = part['type'] as String? ?? 'text';

        switch (type) {
          case 'text':
            wireContent.add({'type': 'text', 'text': part['text'] ?? ''});
            break;
          case 'input_text':
            wireContent.add({'type': 'text', 'text': part['text'] ?? ''});
            break;
          case 'image_url':
            final url = part['image_url'] as Map<String, dynamic>? ?? {};
            wireContent.add({
              'type': 'image',
              'image': url['url'] ?? '',
              'mimeType': url['mime_type'] ?? 'image/png',
            });
            break;
          case 'input_image':
            wireContent.add({
              'type': 'image',
              'image': part['image_url'] ?? '',
              'mimeType': part['mime_type'] ?? 'image/png',
            });
            break;
          case 'reasoning':
          case 'reasoning_content':
            if (allowToolCalls) {
              wireContent.add({'type': 'reasoning', 'text': part['text'] ?? ''});
            }
            break;
        }
      }
    }

    if (allowToolCalls) {
      if (content is List) {
        final embeddedToolCalls = content.whereType<Map>().where((part) {
          final type = part['type'] as String?;
          return type == 'tool_call' || type == 'function';
        });

        for (final toolCall in embeddedToolCalls) {
          wireContent.add(_toWireToolCall(toolCall));
        }
      }

      if (toolCalls is List) {
        for (final toolCall in toolCalls.whereType<Map>()) {
          wireContent.add(_toWireToolCall(toolCall));
        }
      }

      if (functionCall is Map) {
        wireContent.add(_toWireToolCall(functionCall));
      }
    }

    return wireContent;
  }

  Map<String, dynamic> _toWireToolCall(Map toolCall) {
    final rawId = toolCall['id'] ?? toolCall['tool_call_id'] ?? toolCall['toolCallId'];
    final function = toolCall['function'] as Map<String, dynamic>? ?? const {};
    final name = toolCall['name'] as String? ?? function['name'] as String? ?? '';
    final arguments = toolCall['arguments'] ?? function['arguments'];

    return {
      'type': 'tool-call',
      'toolCallId': rawId?.toString() ?? '',
      'toolName': name,
      'input': _decodeToolArguments(arguments),
    };
  }

  Map<String, dynamic> _decodeToolArguments(dynamic arguments) {
    if (arguments is Map<String, dynamic>) return arguments;
    if (arguments is Map) return Map<String, dynamic>.from(arguments);
    if (arguments is String && arguments.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(arguments);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  String _extractTextContent(dynamic content) {
    if (content is String) return content;
    if (content is! List) return '';

    final parts = <String>[];
    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type'] as String? ?? 'text';
      if (type == 'text' || type == 'input_text' || type == 'reasoning' || type == 'reasoning_content') {
        final text = part['text'] as String?;
        if (text != null && text.isNotEmpty) parts.add(text);
      }
    }
    return parts.join('\n');
  }

  Map<String, dynamic> _toOpenAiToolCall(
    Map<String, dynamic> event, {
    int? index,
    bool includeIndex = false,
  }) {
    final input = event['input'];
    final arguments = input == null
        ? '{}'
        : input is String
            ? input
            : input is Map || input is List
                ? jsonEncode(input)
                : '{}';
    return {
      if (includeIndex && index != null) 'index': index,
      'id': event['toolCallId'] ?? event['id'] ?? '',
      'type': 'function',
      'function': {
        'name': event['toolName'] ?? '',
        'arguments': arguments,
      },
    };
  }

  String _extractUpstreamErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        return error['message'] as String? ?? body;
      }
    } catch (_) {}
    return body;
  }

  String _mapFinishReason(String reason) {
    switch (reason) {
      case 'stop':
      case 'end_turn':
        return 'stop';
      case 'max_tokens':
      case 'length':
        return 'length';
      case 'tool_calls':
      case 'tool_use':
        return 'tool_calls';
      case 'content_filter':
        return 'content_filter';
      default:
        return 'stop';
    }
  }

  void _sendSSE(HttpResponse response, Map<String, dynamic> data) {
    response.write('data: ${jsonEncode(data)}\n\n');
  }

  void _sendJson(HttpResponse response, int status, Map<String, dynamic> data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  void _handleModels(HttpRequest request) {
    final models = ModelsDb.all.map((m) => {
          'id': m.id,
          'object': 'model',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'owned_by': m.category,
        }).toList();

    _sendJson(request.response, 200, {
      'object': 'list',
      'data': models,
    });
  }

  void _handleHealth(HttpRequest request) {
    _sendJson(request.response, 200, {
      'status': 'ok',
      'port': configStore.config.serverPort,
      'authenticated': accountStore.isLoaded,
      'version': configStore.config.cliVersion,
    });
  }

  void _handleToken(HttpRequest request) {
    final acc = accountStore.account;
    if (acc == null) {
      _sendJson(request.response, 401, {'error': 'Not authenticated'});
      return;
    }
    _sendJson(request.response, 200, {
      'token': acc.apiKey,
      'user': acc.userName,
    });
  }

  void _handleInfo(HttpRequest request) {
    _sendJson(request.response, 200, {
      'app': 'CommandCode Bridge',
      'version': '1.0.0',
      'port': configStore.config.serverPort,
      'api_url': configStore.config.apiBaseUrl,
      'cli_version': configStore.config.cliVersion,
      'authenticated': accountStore.isLoaded,
      'user': accountStore.account?.userName ?? null,
      'protocol': 'OpenAI Compatible',
    });
  }
}

class _NormalizedRequest {
  final List<Map<String, dynamic>> messages;
  final String? system;

  _NormalizedRequest({required this.messages, required this.system});
}
