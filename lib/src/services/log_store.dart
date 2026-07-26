import 'dart:collection';
import 'dart:convert';
import 'dart:io';

enum LogLevel { debug, info, success, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  LogEntry({required this.level, required this.message, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'message': message,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      level: LogLevel.values.byName(json['level'] as String),
      message: json['message'] as String,
    );
  }
}

class LogStore {
  static const int maxEntries = 2000;
  static final Queue<LogEntry> _entries = Queue();
  static String? _logPath;

  static void init() {
    final home = Platform.environment['HOME'] ?? '/root';
    _logPath = '$home/.config/commandcode-bridge/logs.jsonl';
    final dir = File(_logPath!).parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _loadFromFile();
  }

  static void _loadFromFile() {
    if (_logPath == null) return;
    final file = File(_logPath!);
    if (!file.existsSync()) return;
    try {
      final lines = file.readAsLinesSync();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final entry = LogEntry.fromJson(jsonDecode(line) as Map<String, dynamic>);
          _entries.add(entry);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static void _appendToFile(LogEntry entry) {
    if (_logPath == null) return;
    try {
      final file = File(_logPath!);
      file.writeAsStringSync(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static void _rewriteFile() {
    if (_logPath == null) return;
    try {
      final file = File(_logPath!);
      final lines = _entries.map((e) => jsonEncode(e.toJson())).join('\n');
      file.writeAsStringSync('$lines\n');
    } catch (_) {}
  }

  static void add(LogLevel level, String message) {
    final entry = LogEntry(level: level, message: message);
    _entries.add(entry);
    _appendToFile(entry);
    if (_entries.length > maxEntries) {
      _entries.removeFirst();
      _rewriteFile();
    }
  }

  static void debug(String msg) => add(LogLevel.debug, msg);
  static void info(String msg) => add(LogLevel.info, msg);
  static void success(String msg) => add(LogLevel.success, msg);
  static void warning(String msg) => add(LogLevel.warning, msg);
  static void error(String msg) => add(LogLevel.error, msg);

  static List<LogEntry> get entries => _entries.toList(growable: false);

  static List<LogEntry> get latestFirst {
    final list = _entries.toList(growable: false);
    return list.reversed.toList(growable: false);
  }

  static void clear() {
    _entries.clear();
    if (_logPath != null) {
      File(_logPath!).writeAsStringSync('');
    }
  }

  static void clearBeforeToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _entries.removeWhere((e) => e.timestamp.isBefore(today));
    _rewriteFile();
  }

  static int countBeforeToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _entries.where((e) => e.timestamp.isBefore(today)).length;
  }
}
