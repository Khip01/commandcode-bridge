import 'dart:convert';
import 'dart:io';

class AppAccount {
  final String apiKey;
  final String userId;
  final String userName;
  final String keyName;
  final DateTime authenticatedAt;

  AppAccount({
    required this.apiKey,
    required this.userId,
    required this.userName,
    required this.keyName,
    required this.authenticatedAt,
  });

  factory AppAccount.fromJson(Map<String, dynamic> json) {
    return AppAccount(
      apiKey: json['apiKey'] as String,
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      keyName: json['keyName'] as String? ?? '',
      authenticatedAt: json['authenticatedAt'] != null
          ? DateTime.parse(json['authenticatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'userId': userId,
        'userName': userName,
        'keyName': keyName,
        'authenticatedAt': authenticatedAt.toIso8601String(),
      };
}

String _homeDir() {
  if (Platform.isWindows) {
    return Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
  }
  return Platform.environment['HOME'] ?? '/root';
}

class AccountStore {
  AppAccount? _account;
  String? _error;

  AppAccount? get account => _account;
  String? get error => _error;
  bool get isLoaded => _account != null;

  void load() {
    final home = _homeDir();
    final authFile = File('${home}${Platform.pathSeparator}.commandcode${Platform.pathSeparator}auth.json');
    if (!authFile.existsSync()) {
      _error = 'Auth file not found at $home/.commandcode/auth.json';
      return;
    }
    try {
      final data = jsonDecode(authFile.readAsStringSync()) as Map<String, dynamic>;
      _account = AppAccount.fromJson(data);
      _error = null;
    } catch (e) {
      _error = 'Failed to parse auth file: $e';
    }
  }

  void reload() {
    _account = null;
    _error = null;
    load();
  }
}

class AppConfig {
  static const defaultPort = 17077;

  int serverPort;
  String apiBaseUrl;
  String cliVersion;

  // Port 17077 chosen to avoid neighbors with cobuddy-bridge (20130)
  // and common service ports
  AppConfig({
    this.serverPort = defaultPort,
    this.apiBaseUrl = 'https://api.commandcode.ai',
    this.cliVersion = '1.4.1',
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      serverPort: json['server_port'] as int? ?? defaultPort,
      apiBaseUrl: json['api_base_url'] as String? ?? 'https://api.commandcode.ai',
      cliVersion: json['cli_version'] as String? ?? '1.4.1',
    );
  }

  Map<String, dynamic> toJson() => {
        'server_port': serverPort,
        'api_base_url': apiBaseUrl,
        'cli_version': cliVersion,
      };
}

class ConfigStore {
  AppConfig _config = AppConfig();
  String? _error;

  AppConfig get config => _config;
  String? get error => _error;

  String get _configPath {
    final home = _homeDir();
    return '${home}${Platform.pathSeparator}.config${Platform.pathSeparator}commandcode-bridge${Platform.pathSeparator}config.json';
  }

  void load() {
    final file = File(_configPath);
    if (!file.existsSync()) {
      _config = AppConfig();
      _error = null;
      return;
    }
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _config = AppConfig.fromJson(data);
      _error = null;
    } catch (e) {
      _config = AppConfig();
      _error = 'Failed to parse config: $e';
    }
  }

  void save() {
    final file = File(_configPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(_config.toJson()));
  }
}
