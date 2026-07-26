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

  bool get isRunning => _running;
  String get currentModel => _currentModel;

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
    _running = false;
    _server?.close(force: true);
    _server = null;
    LogStore.info('Proxy server stopped');
  }

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    final method = request.method;

    LogStore.debug('${method.toUpperCase()} $path');

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

      final model = openaiReq['model'] as String? ?? 'deepseek/deepseek-v4-flash';
      final messages = openaiReq['messages'] as List<dynamic>? ?? [];
      final stream = openaiReq['stream'] as bool? ?? false;
      final maxTokens = openaiReq['max_tokens'] as int? ?? 64000;
      final temperature = openaiReq['temperature'] as num?;
      final system = openaiReq['system'] as String?;

      _currentModel = model;
      LogStore.info('Chat: model=$model stream=$stream');

      if (stream) {
        await _proxyStreaming(request.response, acc, model, messages, maxTokens, temperature, system);
      } else {
        await _proxyNonStreaming(request.response, acc, model, messages, maxTokens, temperature, system);
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
    List<dynamic> messages,
    int maxTokens,
    num? temperature,
    String? system,
  ) async {
    final wireMessages = _toWireMessages(messages);

    final body = {
      'params': {
        'model': model,
        'messages': wireMessages,
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
      upstreamReq.headers.set('Content-Type', 'application/json');
      upstreamReq.headers.set('User-Agent', 'cli');
      upstreamReq.headers.set('x-command-code-version', configStore.config.cliVersion);
      upstreamReq.headers.set('x-cli-environment', 'production');

      upstreamReq.write(jsonEncode(body));

      final upstreamRes = await upstreamReq.close();

      response.statusCode = upstreamRes.statusCode;
      response.headers.set('Content-Type', 'text/event-stream');
      response.headers.set('Cache-Control', 'no-cache');
      response.headers.set('Connection', 'keep-alive');

      if (upstreamRes.statusCode == 200) {
        String finishReason = 'stop';
        int inputTokens = 0;
        int outputTokens = 0;
        String leftover = '';

        await for (final raw in upstreamRes) {
          final chunk = utf8.decode(raw);
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
                        'delta': {'content': event['text'] ?? ''},
                        'index': 0,
                      }
                    ],
                  });
                  break;

                case 'reasoning-delta':
                  _sendSSE(response, {
                    'id': event['id'],
                    'object': 'chat.completion.chunk',
                    'choices': [
                      {
                        'delta': {'reasoning_content': event['text'] ?? ''},
                        'index': 0,
                      }
                    ],
                  });
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
                  LogStore.error('API error: $msg');
                  break;
              }
            } catch (_) {}
          }
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
        LogStore.success('Stream completed for model=$model');
      } else {
        final errBytes = await upstreamRes.toList();
        final errBody = utf8.decode(errBytes.expand((b) => b).toList());
        response.write('data: ${jsonEncode({'error': errBody})}\n\n');
      }
    } catch (e) {
      LogStore.error('Streaming proxy error: $e');
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
    List<dynamic> messages,
    int maxTokens,
    num? temperature,
    String? system,
  ) async {
    final wireMessages = _toWireMessages(messages);

    final body = {
      'params': {
        'model': model,
        'messages': wireMessages,
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
      upstreamReq.headers.set('Content-Type', 'application/json');
      upstreamReq.headers.set('User-Agent', 'cli');
      upstreamReq.headers.set('x-command-code-version', configStore.config.cliVersion);
      upstreamReq.headers.set('x-cli-environment', 'production');

      upstreamReq.write(jsonEncode(body));

      final upstreamRes = await upstreamReq.close();

      if (upstreamRes.statusCode != 200) {
        final errBytes = await upstreamRes.toList();
        final errBody = utf8.decode(errBytes.expand((b) => b).toList());
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

      await for (final raw in upstreamRes) {
        final chunk = utf8.decode(raw);
        for (final line in chunk.split('\n')) {
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

      final choice = <String, dynamic>{
        'index': 0,
        'message': {
          'role': 'assistant',
          'content': content,
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

      LogStore.success('Non-streaming completed: tokens_in=$inputTokens tokens_out=$outputTokens');
    } catch (e) {
      LogStore.error('Non-streaming proxy error: $e');
      _sendJson(response, 500, {'error': 'Proxy error: $e'});
    } finally {
      client.close();
    }
  }

  List<Map<String, dynamic>> _toWireMessages(List<dynamic> messages) {
    final result = <Map<String, dynamic>>[];
    for (final msg in messages) {
      final role = msg['role'] as String? ?? 'user';
      final content = msg['content'];
      final wireContent = <Map<String, dynamic>>[];

      if (content is String) {
        wireContent.add({'type': 'text', 'text': content});
      } else if (content is List) {
        for (final part in content) {
          if (part is Map) {
            final type = part['type'] as String? ?? 'text';
            if (type == 'text') {
              wireContent.add({'type': 'text', 'text': part['text'] ?? ''});
            } else if (type == 'image_url') {
              final url = part['image_url'] as Map<String, dynamic>? ?? {};
              wireContent.add({
                'type': 'image',
                'image': url['url'] ?? '',
                'mimeType': 'image/png',
              });
            }
          }
        }
      }

      result.add({'role': role, 'content': wireContent});
    }
    return result;
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
    response.headers.set('Content-Type', 'application/json');
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
