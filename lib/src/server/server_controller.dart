import 'dart:convert';
import 'dart:io';

import '../models/account.dart';
import '../models/models_db.dart';
import '../services/log_store.dart';
import 'openai_handler.dart';
import 'anthropic_handler.dart';

class ServerController {
  HttpServer? _server;
  final AccountStore accountStore;
  final ConfigStore configStore;
  bool _running = false;
  String _currentModel = 'deepseek/deepseek-v4-flash';
  int _modelVersion = 0;

  bool get isRunning => _running;
  String get currentModel => _currentModel;
  int get modelVersion => _modelVersion;

  ServerController({required this.accountStore, required this.configStore});

  Future<void> start() async {
    if (_running) return;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        configStore.config.serverPort,
      );
      _running = true;
      LogStore.success('Bridge started on port ${configStore.config.serverPort}');
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
    LogStore.info('Bridge stopped');
  }

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    final method = request.method;

    try {
      if (path == '/v1/chat/completions' && method == 'POST') {
        _handleOpenAi(request);
      } else if (path == '/v1/messages' && method == 'POST') {
        _handleAnthropic(request);
      } else if (path == '/messages' && method == 'POST') {
        _handleAnthropic(request);
      } else if (path == '/v1/models' && method == 'GET') {
        _handleModels(request);
      } else if (path == '/v1/health' && method == 'GET') {
        _handleHealth(request);
      } else if (path == '/v1/token' && method == 'GET') {
        _handleToken(request);
      } else if (path == '/v1/info' && method == 'GET') {
        _handleInfo(request);
      } else {
        _sendJson(request.response, 404, {
          'error': {'message': 'Not found', 'path': path},
        });
      }
    } catch (e) {
      LogStore.error('Request error: $e');
      _sendJson(request.response, 500, {'error': 'Internal error: $e'});
    }
  }

  Future<void> _handleOpenAi(HttpRequest request) async {
    final acc = accountStore.account;
    if (acc == null) {
      _sendJson(request.response, 401, {
        'error': {'message': 'Not authenticated. Run cmd login first.'},
      });
      return;
    }

    try {
      final handler = OpenAiHandler(
        config: configStore.config,
        acc: acc,
        onModelUsed: (model) {
          _currentModel = model;
          _modelVersion++;
        },
      );
      await handler.handle(request);
    } catch (e) {
      LogStore.error('OpenAI handler error: $e');
      _sendJson(request.response, 500, {'error': 'Internal error: $e'});
    }
  }

  Future<void> _handleAnthropic(HttpRequest request) async {
    final acc = accountStore.account;
    if (acc == null) {
      _sendJson(request.response, 401, {
        'error': {'message': 'Not authenticated. Run cmd login first.'},
      });
      return;
    }

    try {
      final handler = AnthropicHandler(
        config: configStore.config,
        acc: acc,
        onModelUsed: (model) {
          _currentModel = model;
          _modelVersion++;
        },
      );
      await handler.handle(request);
    } catch (e) {
      LogStore.error('Anthropic handler error: $e');
      _sendJson(request.response, 500, {'error': 'Internal error: $e'});
    }
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
      'protocols': ['openai', 'anthropic'],
    });
  }

  void _sendJson(HttpResponse response, int status, Map<String, dynamic> data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }
}
