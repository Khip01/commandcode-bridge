import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/account.dart';
import '../services/log_store.dart';

class AnthropicHandler {
  final AppConfig config;
  final AppAccount acc;
  final void Function(String)? onModelUsed;

  AnthropicHandler({
    required this.config,
    required this.acc,
    this.onModelUsed,
  });

  Future<void> handle(HttpRequest request) async {
    try {
      final bytes = await request.toList();
      final body = utf8.decode(bytes.expand((b) => b).toList());
      final req = jsonDecode(body) as Map<String, dynamic>;
      final stream = req['stream'] as bool? ?? false;

      if (stream) {
        await _handleStreaming(request.response, req);
      } else {
        await _handleNonStreaming(request.response, req);
      }
    } catch (e) {
      LogStore.error('Anthropic handler error: $e');
      _sendJson(request.response, 500, {'error': 'Internal error: $e'});
    }
  }

  Future<void> _handleStreaming(HttpResponse response, Map<String, dynamic> req) async {
    final stopwatch = Stopwatch()..start();
    final model = req['model'] as String? ?? 'deepseek/deepseek-v4-flash';
    onModelUsed?.call(model);
    final maxTokens = (req['max_tokens'] as num?)?.toInt() ?? 64000;
    final temperature = req['temperature'] as num?;
    final system = _extractSystem(req);
    final wireMessages = _toWireMessages(req['messages']);
    final wireTools = _toWireTools(req['tools']);

    final body = _buildUpstreamBody(model, wireMessages, wireTools, maxTokens, temperature, system);

    final client = HttpClient();
    try {
      final upstreamReq = await client.postUrl(
        Uri.parse('${config.apiBaseUrl}/alpha/generate'),
      );
      upstreamReq.headers.set('Authorization', 'Bearer ${acc.apiKey}');
      upstreamReq.headers.contentType = ContentType.json;
      upstreamReq.headers.set('User-Agent', 'cli');
      upstreamReq.headers.set('x-command-code-version', config.cliVersion);
      upstreamReq.headers.set('x-cli-environment', 'production');
      upstreamReq.add(utf8.encode(jsonEncode(body)));

      final upstreamRes = await upstreamReq.close();

      response.statusCode = upstreamRes.statusCode;
      response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      response.headers.set('Cache-Control', 'no-cache');
      response.headers.set('Connection', 'keep-alive');

      if (upstreamRes.statusCode != 200) {
        final errBytes = await upstreamRes.toList();
        final errBody = utf8.decode(errBytes.expand((b) => b).toList());
        LogStore.error('Anthropic upstream rejected ($model): $errBody');
        _sendSSE(response, 'error', {
          'type': 'error',
          'error': {'type': 'api_error', 'message': errBody},
        });
        response.write('event: message_stop\ndata: {"type":"message_stop"}\n\n');
        return;
      }

      String leftover = '';
      bool sentMessageStart = false;
      int contentBlockIndex = 0;
      bool inThinking = false;
      String thinkingText = '';
      bool inText = false;
      bool inToolInput = false;
      String toolInputBuffer = '';
      int inputTokens = 0;
      int outputTokens = 0;
      String finishReason = 'stop';

      final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

      await for (final chunk in utf8.decoder.bind(upstreamRes)) {
        final parts = (leftover + chunk).split('\n');
        leftover = parts.removeLast();

        for (final line in parts) {
          if (line.trim().isEmpty) continue;
          Map<String, dynamic> event;
          try {
            event = jsonDecode(line) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }

          final type = event['type'] as String?;

          switch (type) {
            case 'start':
              break;

            case 'start-step':
              if (!sentMessageStart) {
                _sendSSE(response, 'message_start', {
                  'type': 'message_start',
                  'message': {
                    'id': messageId,
                    'type': 'message',
                    'role': 'assistant',
                    'model': model,
                    'content': const <Map<String, dynamic>>[],
                    'stop_reason': null,
                    'stop_sequence': null,
                    'usage': const {'input_tokens': 0, 'output_tokens': 0},
                  },
                });
                sentMessageStart = true;
              }
              break;

            case 'reasoning-start':
              if (inText) {
                _sendSSE(response, 'content_block_stop', {
                  'type': 'content_block_stop',
                  'index': contentBlockIndex,
                });
                contentBlockIndex++;
                inText = false;
              }
              thinkingText = '';
              inThinking = true;
              break;

            case 'reasoning-delta':
              if (!sentMessageStart) {
                _sendSSE(response, 'message_start', {
                  'type': 'message_start',
                  'message': {
                    'id': messageId,
                    'type': 'message',
                    'role': 'assistant',
                    'model': model,
                    'content': const <Map<String, dynamic>>[],
                    'stop_reason': null,
                    'stop_sequence': null,
                    'usage': const {'input_tokens': 0, 'output_tokens': 0},
                  },
                });
                sentMessageStart = true;
              }
              if (!inThinking) {
                if (inText) {
                  _sendSSE(response, 'content_block_stop', {
                    'type': 'content_block_stop',
                    'index': contentBlockIndex,
                  });
                  contentBlockIndex++;
                  inText = false;
                }
                inThinking = true;
              }
              thinkingText += event['text'] as String? ?? '';
              break;

            case 'reasoning-end':
              _flushThinking(response, contentBlockIndex, thinkingText);
              thinkingText = '';
              inThinking = false;
              contentBlockIndex++;
              break;

            case 'text-delta':
              if (!sentMessageStart) {
                _sendSSE(response, 'message_start', {
                  'type': 'message_start',
                  'message': {
                    'id': messageId,
                    'type': 'message',
                    'role': 'assistant',
                    'model': model,
                    'content': const <Map<String, dynamic>>[],
                    'stop_reason': null,
                    'stop_sequence': null,
                    'usage': const {'input_tokens': 0, 'output_tokens': 0},
                  },
                });
                sentMessageStart = true;
              }
              if (inThinking) {
                _flushThinking(response, contentBlockIndex, thinkingText);
                thinkingText = '';
                inThinking = false;
                contentBlockIndex++;
              }
              if (!inText) {
                _sendSSE(response, 'content_block_start', {
                  'type': 'content_block_start',
                  'index': contentBlockIndex,
                  'content_block': const {'type': 'text', 'text': ''},
                });
                inText = true;
              }
              final text = event['text'] as String? ?? '';
              _sendSSE(response, 'content_block_delta', {
                'type': 'content_block_delta',
                'index': contentBlockIndex,
                'delta': {'type': 'text_delta', 'text': text},
              });
              break;

            case 'text-end':
              if (inText) {
                _sendSSE(response, 'content_block_stop', {
                  'type': 'content_block_stop',
                  'index': contentBlockIndex,
                });
                inText = false;
                contentBlockIndex++;
              }
              break;

            case 'tool-input-start':
              LogStore.info('Anthropic tool-input-start: toolName=${event['toolName']} toolCallId=${event['toolCallId']}');
              if (!sentMessageStart) {
                _sendSSE(response, 'message_start', {
                  'type': 'message_start',
                  'message': {
                    'id': messageId,
                    'type': 'message',
                    'role': 'assistant',
                    'model': model,
                    'content': const <Map<String, dynamic>>[],
                    'stop_reason': null,
                    'stop_sequence': null,
                    'usage': const {'input_tokens': 0, 'output_tokens': 0},
                  },
                });
                sentMessageStart = true;
              }
              if (inThinking) {
                _flushThinking(response, contentBlockIndex, thinkingText);
                thinkingText = '';
                inThinking = false;
                contentBlockIndex++;
              }
              if (inText) {
                _sendSSE(response, 'content_block_stop', {
                  'type': 'content_block_stop',
                  'index': contentBlockIndex,
                });
                inText = false;
                contentBlockIndex++;
              }
              inToolInput = true;
              break;

            case 'tool-input-delta':
              if (inToolInput) {
                toolInputBuffer += event['text'] as String? ?? '';
              }
              break;

            case 'tool-input-end':
              LogStore.info('Anthropic tool-input-end: buffer=${toolInputBuffer.length}chars');
              break;

            case 'tool-call':
              if (!sentMessageStart) {
                _sendSSE(response, 'message_start', {
                  'type': 'message_start',
                  'message': {
                    'id': messageId,
                    'type': 'message',
                    'role': 'assistant',
                    'model': model,
                    'content': const <Map<String, dynamic>>[],
                    'stop_reason': null,
                    'stop_sequence': null,
                    'usage': const {'input_tokens': 0, 'output_tokens': 0},
                  },
                });
                sentMessageStart = true;
              }
              if (inThinking) {
                _flushThinking(response, contentBlockIndex, thinkingText);
                thinkingText = '';
                inThinking = false;
                contentBlockIndex++;
              }
              if (inText) {
                _sendSSE(response, 'content_block_stop', {
                  'type': 'content_block_stop',
                  'index': contentBlockIndex,
                });
                inText = false;
                contentBlockIndex++;
              }
              final toolId = event['toolCallId'] as String? ?? _generateToolId();
              final toolName = event['toolName'] as String? ?? '';
              final input = event['input'];
              final inputStr = input is String ? input : jsonEncode(input ?? {});
              LogStore.info('Anthropic tool-call: name=$toolName input=$inputStr');

              _sendSSE(response, 'content_block_start', {
                'type': 'content_block_start',
                'index': contentBlockIndex,
                'content_block': {
                  'type': 'tool_use',
                  'id': toolId,
                  'name': toolName,
                  'input': const <String, dynamic>{},
                },
              });
              _sendSSE(response, 'content_block_delta', {
                'type': 'content_block_delta',
                'index': contentBlockIndex,
                'delta': {
                  'type': 'input_json_delta',
                  'partial_json': inputStr,
                },
              });
              _sendSSE(response, 'content_block_stop', {
                'type': 'content_block_stop',
                'index': contentBlockIndex,
              });
              toolInputBuffer = '';
              inToolInput = false;
              contentBlockIndex++;
              break;

            case 'finish-step':
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
              _sendSSE(response, 'error', {
                'type': 'error',
                'error': {'type': 'api_error', 'message': msg},
              });
              LogStore.error('Anthropic upstream error ($model): $msg');
              break;

            case 'abort':
              response.write('event: message_stop\ndata: {"type":"message_stop"}\n\n');
              return;

            case 'provider-metadata':
              break;

            default:
              break;
          }
        }
      }

      if (leftover.trim().isNotEmpty) {
        try {
          final event = jsonDecode(leftover.trim()) as Map<String, dynamic>;
          if (event['type'] == 'finish') {
            finishReason = event['finishReason'] as String? ?? 'stop';
            final usage = event['totalUsage'] as Map<String, dynamic>?;
            if (usage != null) {
              inputTokens = (usage['inputTokens'] as num?)?.toInt() ?? 0;
              outputTokens = (usage['outputTokens'] as num?)?.toInt() ?? 0;
            }
          }
        } catch (_) {}
      }

      if (inThinking) {
        _flushThinking(response, contentBlockIndex, thinkingText);
        contentBlockIndex++;
      }
      if (inText) {
        _sendSSE(response, 'content_block_stop', {
          'type': 'content_block_stop',
          'index': contentBlockIndex,
        });
        contentBlockIndex++;
      }

      if (finishReason == 'pause_turn') {
        finishReason = 'end_turn';
      }

      _sendSSE(response, 'message_delta', {
        'type': 'message_delta',
        'delta': {
          'stop_reason': _toAnthropicStopReason(finishReason),
          'stop_sequence': null,
        },
        'usage': {'output_tokens': outputTokens},
      });

      response.write('event: message_stop\ndata: {"type":"message_stop"}\n\n');

      LogStore.success(
        'Anthropic chat ok ($model, ${stopwatch.elapsed.inMilliseconds}ms, in=$inputTokens, out=$outputTokens)',
      );
    } catch (e) {
      LogStore.error('Anthropic streaming error ($model): $e');
      try {
        _sendSSE(response, 'error', {
          'type': 'error',
          'error': {'type': 'proxy_error', 'message': 'Proxy error: $e'},
        });
        response.write('event: message_stop\ndata: {"type":"message_stop"}\n\n');
      } catch (_) {}
    } finally {
      client.close();
      try {
        await response.flush();
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleNonStreaming(HttpResponse response, Map<String, dynamic> req) async {
    final stopwatch = Stopwatch()..start();
    final model = req['model'] as String? ?? 'deepseek/deepseek-v4-flash';
    onModelUsed?.call(model);
    final maxTokens = (req['max_tokens'] as num?)?.toInt() ?? 64000;
    final temperature = req['temperature'] as num?;
    final system = _extractSystem(req);
    final wireMessages = _toWireMessages(req['messages']);
    final wireTools = _toWireTools(req['tools']);

    final body = _buildUpstreamBody(model, wireMessages, wireTools, maxTokens, temperature, system);

    final client = HttpClient();
    try {
      final upstreamReq = await client.postUrl(
        Uri.parse('${config.apiBaseUrl}/alpha/generate'),
      );
      upstreamReq.headers.set('Authorization', 'Bearer ${acc.apiKey}');
      upstreamReq.headers.contentType = ContentType.json;
      upstreamReq.headers.set('User-Agent', 'cli');
      upstreamReq.headers.set('x-command-code-version', config.cliVersion);
      upstreamReq.headers.set('x-cli-environment', 'production');
      upstreamReq.add(utf8.encode(jsonEncode(body)));

      final upstreamRes = await upstreamReq.close();

      if (upstreamRes.statusCode != 200) {
        final errBytes = await upstreamRes.toList();
        final errBody = utf8.decode(errBytes.expand((b) => b).toList());
        _sendJson(response, upstreamRes.statusCode, {'error': errBody});
        return;
      }

      String textContent = '';
      String thinking = '';
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
            switch (event['type']) {
              case 'text-delta':
                textContent += event['text'] as String? ?? '';
                break;
              case 'reasoning-delta':
                thinking += event['text'] as String? ?? '';
                break;
              case 'tool-call':
                final input = event['input'];
                toolCalls.add({
                  'id': event['toolCallId'] ?? '',
                  'name': event['toolName'] ?? '',
                  'input': input is Map ? input : (input is String ? jsonDecode(input) : {}),
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
            }
          } catch (_) {}
        }
      }

      final content = <Map<String, dynamic>>[];
      if (thinking.isNotEmpty) {
        content.add({'type': 'thinking', 'thinking': thinking, 'signature': ''});
      }
      if (textContent.isNotEmpty) {
        content.add({'type': 'text', 'text': textContent});
      }
      for (final tc in toolCalls) {
        content.add({
          'type': 'tool_use',
          'id': tc['id'],
          'name': tc['name'],
          'input': tc['input'],
        });
      }

      _sendJson(response, 200, {
        'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'message',
        'role': 'assistant',
        'model': model,
        'content': content,
        'stop_reason': _toAnthropicStopReason(finishReason),
        'stop_sequence': null,
        'usage': {
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
        },
      });

      LogStore.success(
        'Anthropic chat ok ($model, ${stopwatch.elapsed.inMilliseconds}ms, in=$inputTokens, out=$outputTokens)',
      );
    } catch (e) {
      LogStore.error('Anthropic non-streaming error ($model): $e');
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

  String? _extractSystem(Map<String, dynamic> req) {
    if (req['system'] is String) {
      final s = req['system'] as String;
      if (s.trim().isNotEmpty) return s.trim();
    }
    if (req['system'] is List) {
      final parts = <String>[];
      for (final part in (req['system'] as List)) {
        if (part is Map && part['type'] == 'text') {
          final text = part['text'] as String? ?? '';
          if (text.isNotEmpty) parts.add(text);
        }
      }
      if (parts.isNotEmpty) return parts.join('\n\n');
    }
    return null;
  }

  List<Map<String, dynamic>> _toWireTools(dynamic tools) {
    if (tools is! List) return const [];
    final result = <Map<String, dynamic>>[];
    for (final raw in tools) {
      if (raw is! Map) continue;
      final name = raw['name'] as String?;
      if (name == null || name.isEmpty) continue;
      result.add({
        'name': name,
        'description': raw['description'] as String? ?? '',
        'input_schema': _toInputSchema(raw['input_schema']),
      });
    }
    return result;
  }

  Map<String, dynamic> _toInputSchema(dynamic schema) {
    if (schema is Map<String, dynamic>) return schema;
    if (schema is Map) return Map<String, dynamic>.from(schema);
    return {
      'type': 'object',
      'properties': const <String, dynamic>{},
      'required': const <String>[],
      'additionalProperties': true,
    };
  }

  List<Map<String, dynamic>> _toWireMessages(dynamic messages) {
    if (messages is! List) return const [];
    final result = <Map<String, dynamic>>[];

    for (final raw in messages) {
      if (raw is! Map) continue;
      final role = raw['role'] as String? ?? 'user';
      final content = raw['content'];

      if (content is String) {
        final wireRole = role == 'assistant' ? 'assistant' : 'user';
        result.add({
          'role': wireRole,
          'content': [{'type': 'text', 'text': content}],
        });
        continue;
      }

      if (content is! List) continue;

      if (role == 'assistant') {
        final wireContent = <Map<String, dynamic>>[];
        for (final block in content) {
          if (block is! Map) continue;
          final blockType = block['type'] as String?;
          if (blockType == 'text') {
            wireContent.add({'type': 'text', 'text': block['text'] ?? ''});
          } else if (blockType == 'tool_use') {
            wireContent.add({
              'type': 'tool-call',
              'toolCallId': block['id'] ?? '',
              'toolName': block['name'] ?? '',
              'input': block['input'] ?? {},
            });
          } else if (blockType == 'thinking') {
            wireContent.add({'type': 'reasoning', 'text': block['thinking'] ?? ''});
          }
        }
        if (wireContent.isNotEmpty) {
          result.add({'role': 'assistant', 'content': wireContent});
        }
        continue;
      }

      if (role == 'user') {
        final wireContent = <Map<String, dynamic>>[];
        bool hasContent = false;
        for (final block in content) {
          if (block is! Map) continue;
          final blockType = block['type'] as String?;
          if (blockType == 'text') {
            final text = block['text'] as String? ?? '';
            if (text.isNotEmpty) {
              wireContent.add({'type': 'text', 'text': text});
              hasContent = true;
            }
          } else if (blockType == 'image' || blockType == 'image_url') {
            final source = block['source'] as Map<String, dynamic>? ?? {};
            wireContent.add({
              'type': 'image',
              'image': 'data:${source['media_type'] ?? 'image/png'};base64,${source['data'] ?? ''}',
              'mimeType': source['media_type'] ?? 'image/png',
            });
            hasContent = true;
          } else if (blockType == 'tool_result') {
            final outputContent = block['content'];
            var value = '';
            if (outputContent is String) {
              value = outputContent;
            } else if (outputContent is List) {
              final texts = <String>[];
              for (final c in outputContent) {
                if (c is Map && c['type'] == 'text') {
                  texts.add(c['text'] as String? ?? '');
                }
              }
              value = texts.join('\n');
            }
            result.add({
              'role': 'tool',
              'content': [
                {
                  'type': 'tool-result',
                  'toolCallId': block['tool_use_id'] ?? '',
                  'toolName': '',
                  'output': {'type': 'text', 'value': value},
                }
              ],
            });
          }
        }
        if (hasContent) {
          result.add({'role': 'user', 'content': wireContent});
        }
      }
    }

    return result;
  }

  String _generateToolId() {
    final r = Random();
    final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final suffix = List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
    return 'toolu_${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }

  void _flushThinking(HttpResponse response, int index, String text) {
    if (text.isEmpty) return;
    _sendSSE(response, 'content_block_start', {
      'type': 'content_block_start',
      'index': index,
      'content_block': {'type': 'thinking', 'thinking': text, 'signature': ''},
    });
    _sendSSE(response, 'content_block_stop', {
      'type': 'content_block_stop',
      'index': index,
    });
  }

  void _sendSSE(HttpResponse response, String event, Map<String, dynamic> data) {
    response.write('event: $event\ndata: ${jsonEncode(data)}\n\n');
  }

  void _sendJson(HttpResponse response, int status, Map<String, dynamic> data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  String _toAnthropicStopReason(String reason) {
    switch (reason) {
      case 'stop':
      case 'end_turn':
        return 'end_turn';
      case 'max_tokens':
      case 'length':
        return 'max_tokens';
      case 'tool_calls':
      case 'tool_use':
        return 'tool_use';
      default:
        return 'end_turn';
    }
  }
}
