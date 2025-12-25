import 'dart:async';
import 'package:flutter/services.dart';

class UsageStatsService {
  static const platform = MethodChannel('com.flaming.cherubim/stats');
  
  final StreamController<UsageStats> _statsController = StreamController<UsageStats>.broadcast();
  Timer? _updateTimer;
  
  UsageStats _currentStats = UsageStats(
    uploadBytes: 0,
    downloadBytes: 0,
    memoryMB: 0,
  );

  Stream<UsageStats> get statsStream => _statsController.stream;
  UsageStats get currentStats => _currentStats;

  void startMonitoring() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _fetchStats();
    });
  }

  void stopMonitoring() {
    _updateTimer?.cancel();
  }

  Future<void> _fetchStats() async {
    try {
      final result = await platform.invokeMethod('getUsageStats');
      if (result != null) {
        _currentStats = UsageStats(
          uploadBytes: result['upload'] ?? 0,
          downloadBytes: result['download'] ?? 0,
          memoryMB: result['memory'] ?? 0,
        );
        _statsController.add(_currentStats);
      }
    } catch (e) {
      // Stats fetch failed, ignore
    }
  }

  void dispose() {
    _updateTimer?.cancel();
    _statsController.close();
  }
}

class UsageStats {
  final int uploadBytes;
  final int downloadBytes;
  final double memoryMB;

  UsageStats({
    required this.uploadBytes,
    required this.downloadBytes,
    required this.memoryMB,
  });

  String get uploadFormatted => _formatBytes(uploadBytes);
  String get downloadFormatted => _formatBytes(downloadBytes);
  String get memoryFormatted => '${memoryMB.toStringAsFixed(1)} MB';

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
