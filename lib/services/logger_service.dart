import 'dart:async';
import 'dart:convert';

class LogEntry {
  final String message;
  final DateTime timestamp;
  final String level; // 'INFO', 'ERROR', 'WARNING', 'DEBUG'
  final StackTrace? stackTrace;

  LogEntry({required this.message, required this.timestamp, this.level = 'INFO', this.stackTrace});

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  String toString() {
    final baseMsg = '[$formattedTime] [$level] $message';
    if (stackTrace != null) {
      return '$baseMsg\nStack trace:\n$stackTrace';
    }
    return baseMsg;
  }
}

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  final List<LogEntry> _logs = [];
  final StreamController<LogEntry> _logController = StreamController<LogEntry>.broadcast();

  // Increased buffer size for more log history
  static const int _maxLogEntries = 1000;

  LoggerService._internal();

  factory LoggerService() {
    return _instance;
  }

  Stream<LogEntry> get logsStream => _logController.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  int get logsCount => _logs.length;

  void log(String message, {String level = 'INFO', StackTrace? stackTrace}) {
    final entry = LogEntry(message: message, timestamp: DateTime.now(), level: level, stackTrace: stackTrace);

    _logs.add(entry);

    // Keep only last N entries to avoid memory issues
    if (_logs.length > _maxLogEntries) {
      _logs.removeAt(0);
    }

    _logController.add(entry);
    // Print to console for debug visibility
    print(entry.toString());
  }

  void info(String message) => log(message, level: 'INFO');

  void error(String message, {StackTrace? stackTrace}) => log(message, level: 'ERROR', stackTrace: stackTrace);

  void warning(String message) => log(message, level: 'WARNING');

  void debug(String message) => log(message, level: 'DEBUG');

  // Log objects/maps for debugging (e.g., V2Ray config)
  void logObject(String prefix, Object? object, {String level = 'DEBUG'}) {
    try {
      final jsonStr = JsonEncoder.withIndent('  ').convert(object);
      log('$prefix:\n$jsonStr', level: level);
    } catch (e) {
      log('$prefix: ${object.toString()}', level: level);
    }
  }

  // Get logs filtered by level
  List<LogEntry> getLogsByLevel(String level) {
    return _logs.where((entry) => entry.level == level).toList();
  }

  // Get recent logs (last N entries)
  List<LogEntry> getRecentLogs(int count) {
    final startIndex = _logs.length > count ? _logs.length - count : 0;
    return _logs.sublist(startIndex);
  }

  void clearLogs() {
    _logs.clear();
  }

  String getAllLogsAsString() {
    return _logs.map((entry) => entry.toString()).join('\n');
  }

  void dispose() {
    _logController.close();
  }
}
