import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/account.dart';
import '../services/log_store.dart';

typedef OnModelUsed = void Function(String model);

class OpenAiHandler {
  final AppConfig config;
  final AppAccount acc;
  final OnModelUsed? onModelUsed;

  OpenAiHandler({
    required this.config,
    required this.acc,
    this.onModelUsed,
  });

  Future<void> handle(HttpRequest request) async {
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

      onModelUsed?.call(model);

      if (stream) {
        await _stream(request.response, model, normalized.messages, tools,
            maxTokens, temperature, normalized.system);
      } else {
        await _nonStream(request.response, model, normalized.messages, tools,
            maxTokens, temperature, normalized.system);
      }
    } catch (e) {
      LogStore.error('OpenAI handler error: $e');
      _sendJson(request.response, 500, {'error': 'Internal error: $e'});
    }
  }

  Future<void> _stream(
    HttpResponse response,
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
    int maxTokens,
    num? temperature,
    String? system,
  ) async {
    final stopwatch = Stopwatch()..start();
    final body = _buildUpstreamBody(model, messages, tools, maxTokens, temperature, system);

    final client = HttpClient();
    try {
      final upstreamRes = await _sendUpstream(client, body);

      response.statusCode = upstreamRes.statusCode;
      response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      response.headers.set('Cache-Control', 'no-cache');
      response.headers.set('Connection', 'keep-alive');

      if (upstreamRes.statusCode != 200) {
        final errBody = await _readErrorBody(upstreamRes);
        _sendSSE(response, {
          'error': {'message': errBody, 'type': 'upstream_error'},
        });
        return;
      }

      String finishReason = 'stop';
      int inputTokens = 0;
      int outputTokens = 0;
      String leftover = '';
      bool sentRole = false;
      bool sawFinish = false;
      final toolCalls = <Map<String, dynamic>>[];

      await for (final chunk in utf8.decoder.bind(upstreamRes)) {
        final parts = (leftover + chunk).split('\n');
        leftover = parts.removeLast();

        for (final line in parts) {
          if (line.trim().isEmpty) continue;
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            switch (event['type'] as String?) {
              case 'text-delta':
                _sendSSE(response, {
                  'id': event['id'],
                  'object': 'chat.completion.chunk',
                  'choices': [
                    {
                      'delta': {
                        if (!sentRole) 'role': 'assistant',
                        'content': event['text'] ?? '',
                      },
                      'index': 0,
                    }
                  ],
                });
                sentRole = true;
                break;

              case 'reasoning-delta':
                _sendSSE(response, {
                  'id': event['id'],
                  'object': 'chat.completion.chunk',
                  'choices': [
                    {
                      'delta': {
                        if (!sentRole) 'role': 'assistant',
                        'reasoning_content': event['text'] ?? '',
                      },
                      'index': 0,
                    }
                  ],
                });
                sentRole = true;
                break;

              case 'tool-call':
                final tc = _toOpenAiToolCall(event, index: toolCalls.length);
                toolCalls.add(tc);
                _sendSSE(response, {
                  'id': event['id'],
                  'object': 'chat.completion.chunk',
                  'choices': [
                    {
                      'delta': {
                        if (!sentRole) 'role': 'assistant',
                        'tool_calls': [tc],
                      },
                      'index': 0,
                    }
                  ],
                });
                sentRole = true;
                break;

              case 'finish':
                sawFinish = true;
                finishReason = event['finishReason'] as String? ?? 'stop';
                final u = event['totalUsage'] as Map<String, dynamic>?;
                if (u != null) {
                  inputTokens = (u['inputTokens'] as num?)?.toInt() ?? 0;
                  outputTokens = (u['outputTokens'] as num?)?.toInt() ?? 0;
                }
                break;

              case 'error':
                final err = event['error'] as Map<String, dynamic>?;
                final msg = err?['message'] as String? ?? 'Unknown error';
                _sendSSE(response, {
                  'error': {'message': msg, 'type': 'api_error'},
                });
                LogStore.error('OpenAI upstream error ($model): $msg');
                break;

              case 'abort':
                sawFinish = true;
                break;
            }
          } catch (_) {}
        }
      }

      if (leftover.trim().isNotEmpty) {
        try {
          final event = jsonDecode(leftover.trim()) as Map<String, dynamic>;
          if (event['type'] == 'finish') {
            sawFinish = true;
            finishReason = event['finishReason'] as String? ?? 'stop';
            final u = event['totalUsage'] as Map<String, dynamic>?;
            if (u != null) {
              inputTokens = (u['inputTokens'] as num?)?.toInt() ?? 0;
              outputTokens = (u['outputTokens'] as num?)?.toInt() ?? 0;
            }
          }
        } catch (_) {}
      }

      if (finishReason == 'pause_turn') finishReason = 'stop';
      if (toolCalls.isNotEmpty && finishReason == 'stop') finishReason = 'tool_calls';
      if (!sawFinish) {
        LogStore.warning('OpenAI stream truncated ($model)');
        finishReason = 'length';
      }

      _sendSSE(response, {
        'id': 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
        'object': 'chat.completion.chunk',
        'choices': [
          {
            'delta': const <String, dynamic>{},
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
        'OpenAI ok ($model, ${stopwatch.elapsed.inMilliseconds}ms, in=$inputTokens, out=$outputTokens${toolCalls.isNotEmpty ? ', tools=${toolCalls.length}' : ''})',
      );
    } catch (e) {
      LogStore.error('OpenAI stream error ($model): $e');
      try {
        _sendSSE(response, {
          'error': {'message': 'Proxy error: $e', 'type': 'proxy_error'},
        });
      } catch (_) {}
    } finally {
      client.close();
      try {
        await response.flush();
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _nonStream(
    HttpResponse response,
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
    int maxTokens,
    num? temperature,
    String? system,
  ) async {
    final stopwatch = Stopwatch()..start();
    final body = _buildUpstreamBody(model, messages, tools, maxTokens, temperature, system);

    final client = HttpClient();
    try {
      final upstreamRes = await _sendUpstream(client, body);

      if (upstreamRes.statusCode != 200) {
        final errBody = await _readErrorBody(upstreamRes);
        _sendJson(response, upstreamRes.statusCode, {
          'error': {'message': errBody, 'type': 'upstream_error'},
        });
        return;
      }

      String content = '';
      String? reasoning;
      String finishReason = 'stop';
      int inputTokens = 0;
      int outputTokens = 0;
      final toolCalls = <Map<String, dynamic>>[];
      String leftover = '';

      await for (final bytes in upstreamRes) {
        final chunk = utf8.decode(bytes);
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
                final u = event['totalUsage'] as Map<String, dynamic>?;
                if (u != null) {
                  inputTokens = (u['inputTokens'] as num?)?.toInt() ?? 0;
                  outputTokens = (u['outputTokens'] as num?)?.toInt() ?? 0;
                }
                break;
            }
          } catch (_) {}
        }
      }

      if (toolCalls.isNotEmpty && finishReason == 'stop') finishReason = 'tool_calls';

      final choice = <String, dynamic>{
        'index': 0,
        'message': <String, dynamic>{
          'role': 'assistant',
          'content': content,
          if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
          if (reasoning != null && reasoning.isNotEmpty) 'reasoning_content': reasoning,
        },
        'finish_reason': _mapFinishReason(finishReason),
      };

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
        'OpenAI ok ($model, ${stopwatch.elapsed.inMilliseconds}ms, in=$inputTokens, out=$outputTokens${toolCalls.isNotEmpty ? ', tools=${toolCalls.length}' : ''})',
      );
    } catch (e) {
      LogStore.error('OpenAI non-stream error ($model): $e');
      _sendJson(response, 500, {'error': 'Proxy error: $e'});
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _buildUpstreamBody(
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
    int maxTokens,
    num? temperature,
    String? system,
  ) {
    return {
      'params': {
        'model': model,
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
        'stream': true,
        'max_tokens': maxTokens,
        if (temperature != null) 'temperature': temperature.toDouble(),
        if (system != null) 'system': system,
      },
      'config': {
        'workingDir': '/tmp',
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'environment': 'production',
        'structure': const <String>[],
        'isGitRepo': false,
        'currentBranch': '',
        'mainBranch': '',
        'gitStatus': '',
        'recentCommits': const <String>[],
      },
      'memory': null,
      'taste': null,
      'skills': null,
      'permissionMode': 'standard',
    };
  }

  Future<HttpClientResponse> _sendUpstream(HttpClient client, Map<String, dynamic> body) async {
    final req = await client.postUrl(
      Uri.parse('${config.apiBaseUrl}/alpha/generate'),
    );
    req.headers.set('Authorization', 'Bearer ${acc.apiKey}');
    req.headers.contentType = ContentType.json;
    req.headers.set('User-Agent', 'cli');
    req.headers.set('x-command-code-version', config.cliVersion);
    req.headers.set('x-cli-environment', 'production');
    req.add(utf8.encode(jsonEncode(body)));
    return req.close();
  }

  Future<String> _readErrorBody(HttpClientResponse res) async {
    try {
      final bytes = await res.toList();
      final body = utf8.decode(bytes.expand((b) => b).toList());
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        return error['message'] as String? ?? body;
      }
      return body;
    } catch (_) {
      return 'Upstream error (${res.statusCode})';
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
        final tr = _toWireToolMessage(raw);
        if (tr != null) normalized.add(tr);
        continue;
      }

      final msg = _toWireMessage(raw);
      if (msg != null) normalized.add(msg);
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
    if (content.isEmpty && role == 'assistant') {
      return {'role': wireRole, 'content': const <Map<String, dynamic>>[]};
    }
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
          'output': {'type': 'text', 'value': outputText},
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
      'properties': const <String, dynamic>{},
      'required': const <String>[],
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
        for (final part in content.whereType<Map>()) {
          final type = part['type'] as String?;
          if (type == 'tool_call' || type == 'function') {
            wireContent.add(_toWireToolCall(part));
          }
        }
      }
      if (toolCalls is List) {
        for (final tc in toolCalls.whereType<Map>()) {
          wireContent.add(_toWireToolCall(tc));
        }
      }
      if (functionCall is Map) {
        wireContent.add(_toWireToolCall(functionCall));
      }
    }

    return wireContent;
  }

  Map<String, dynamic> _toWireToolCall(Map tc) {
    final rawId = tc['id'] ?? tc['tool_call_id'] ?? tc['toolCallId'];
    final function = tc['function'] as Map<String, dynamic>? ?? const {};
    final name = tc['name'] as String? ?? function['name'] as String? ?? '';
    final arguments = tc['arguments'] ?? function['arguments'];
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
      if (type == 'text' ||
          type == 'input_text' ||
          type == 'reasoning' ||
          type == 'reasoning_content') {
        final text = part['text'] as String?;
        if (text != null && text.isNotEmpty) parts.add(text);
      }
    }
    return parts.join('\n');
  }

  Map<String, dynamic> _toOpenAiToolCall(Map<String, dynamic> event, {int? index}) {
    final input = event['input'];
    final arguments = input == null
        ? '{}'
        : input is String
            ? input
            : input is Map || input is List
                ? jsonEncode(input)
                : '{}';
    return {
      if (index != null) 'index': index,
      'id': event['toolCallId'] ?? event['id'] ?? '',
      'type': 'function',
      'function': {
        'name': event['toolName'] ?? '',
        'arguments': arguments,
      },
    };
  }

  String _mapFinishReason(String reason) {
    switch (reason) {
      case 'end_turn':
        return 'stop';
      case 'max_tokens':
        return 'length';
      case 'tool_use':
        return 'tool_calls';
      default:
        return reason;
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
}

class _NormalizedRequest {
  final List<Map<String, dynamic>> messages;
  final String? system;
  _NormalizedRequest({required this.messages, required this.system});
}
