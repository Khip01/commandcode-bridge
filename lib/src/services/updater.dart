import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/version.dart';
import 'log_store.dart';

class UpdateResult {
  final bool success;
  final String? message;

  UpdateResult({required this.success, this.message});

  factory UpdateResult.ok(String message) => UpdateResult(success: true, message: message);
  factory UpdateResult.fail(String message) => UpdateResult(success: false, message: message);
}

class Updater {
  static const _owner = 'Khip01';
  static const _repo = 'commandcode-bridge';
  static const _apiBase = 'https://api.github.com';
  static const _dlBase = 'https://github.com/$_owner/$_repo/releases/download';
  static const _cacheTtlMs = 3_600_000; // 1 hour

  final http.Client _client;
  final String _cacheFile;

  Updater({http.Client? client})
      : _client = client ?? http.Client(),
        _cacheFile = _cachePath();

  static String _configDir() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Platform.environment['LOCALAPPDATA'] ?? 'C:\\Users\\Default\\AppData\\Roaming';
      return '$appData${Platform.pathSeparator}commandcode-bridge';
    }
    final home = Platform.environment['HOME'] ?? '/root';
    return '$home${Platform.pathSeparator}.config${Platform.pathSeparator}commandcode-bridge';
  }

  static String _cachePath() => '${_configDir()}${Platform.pathSeparator}update-cache.json';

  String? _readCache() {
    try {
      final f = File(_cacheFile);
      if (!f.existsSync()) return null;
      final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final at = (data['at'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at > _cacheTtlMs) return null;
      return data['tag'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _writeCache(String tag) {
    try {
      final dir = Directory(_configDir());
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_cacheFile).writeAsStringSync(jsonEncode({
        'tag': tag,
        'at': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  Future<String?> _fetchLatestTag() async {
    final cached = _readCache();
    if (cached != null) return cached;

    try {
      final res = await _client.get(
        Uri.parse('$_apiBase/repos/$_owner/$_repo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'commandcode-bridge-cli',
        },
      );
      if (res.statusCode != 200) return cached;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String?;
      if (tag != null) _writeCache(tag);
      return tag;
    } catch (_) {
      return cached;
    }
  }

  List<int>? _parseSemver(String v) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
    if (m == null) return null;
    return [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
  }

  int _compareSemver(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return 0;
  }

  String? _findNpm() {
    try {
      final result = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        ['npm'],
      );
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        final lines = out.split('\n');
        if (lines.isNotEmpty) return lines.first.trim();
      }
    } catch (_) {}
    return null;
  }

  String? _resolveGlobalInstallPath() {
    try {
      final result = Process.runSync('npm', ['root', '-g']);
      if (result.exitCode == 0) {
        final root = (result.stdout as String).trim();
        if (root.isNotEmpty) return '$root${Platform.pathSeparator}$_repo';
      }
    } catch (_) {}
    // Fallback
    return '${Platform.resolvedExecutable}${Platform.pathSeparator}..${Platform.pathSeparator}lib${Platform.pathSeparator}node_modules${Platform.pathSeparator}$_repo';
  }

  String? _cleanExistingInstall() {
    final target = _resolveGlobalInstallPath();
    if (target == null) return null;
    try {
      final dir = Directory(target);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      return target;
    } catch (_) {
      return null;
    }
  }

  Future<UpdateResult> update() async {
    final tag = await _fetchLatestTag();
    if (tag == null) {
      return UpdateResult.fail('Failed to check latest version from GitHub');
    }

    final latestVer = _parseSemver(tag);
    final currentVer = _parseSemver(bridgeVersion);
    if (latestVer == null || currentVer == null) {
      return UpdateResult.fail('Cannot parse version (current: $bridgeVersion, latest: $tag)');
    }

    if (_compareSemver(latestVer, currentVer) <= 0) {
      return UpdateResult.ok('Already up to date (latest: $tag).');
    }

    final assetUrl = '$_dlBase/$tag/commandcode-bridge-$tag.tgz';

    final tmpDir = Directory.systemTemp.createTempSync('ccb-install-');
    final tgzPath = '${tmpDir.path}${Platform.pathSeparator}commandcode-bridge-$tag.tgz';

    try {
      print('Downloading from $assetUrl...');
      final res = await _client.get(Uri.parse(assetUrl));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        return UpdateResult.fail('Download failed: HTTP ${res.statusCode}');
      }
      File(tgzPath).writeAsBytesSync(res.bodyBytes);
      print('Downloaded commandcode-bridge-$tag.tgz');

      final cleaned = _cleanExistingInstall();
      if (cleaned != null) {
        print('Removed previous install at $cleaned');
      }

      final npm = _findNpm();
      if (npm == null) {
        return UpdateResult.fail('npm not found in PATH. Is Node.js installed?');
      }

      print('Installing...');
      final result = await Process.run(
        npm,
        ['install', '-g', tgzPath],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        return UpdateResult.fail('npm install failed:\n${result.stderr}');
      }

      LogStore.info('Updated to $tag');
      return UpdateResult.ok('Updated to $tag.');
    } finally {
      try { tmpDir.deleteSync(recursive: true); } catch (_) {}
    }
  }

  void dispose() {
    _client.close();
  }
}
