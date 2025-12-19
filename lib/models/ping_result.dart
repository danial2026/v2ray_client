class PingResult {
  final String serverId;
  final int? latencyMs;
  final bool isSuccess;
  final DateTime timestamp;
  final String? errorMessage;

  PingResult({required this.serverId, this.latencyMs, required this.isSuccess, required this.timestamp, this.errorMessage});

  // Create success result
  factory PingResult.success({required String serverId, required int latencyMs}) {
    return PingResult(serverId: serverId, latencyMs: latencyMs, isSuccess: true, timestamp: DateTime.now());
  }

  // Create failure result
  factory PingResult.failure({required String serverId, required String errorMessage}) {
    return PingResult(serverId: serverId, isSuccess: false, timestamp: DateTime.now(), errorMessage: errorMessage);
  }

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'latencyMs': latencyMs,
      'isSuccess': isSuccess,
      'timestamp': timestamp.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }

  // Create from JSON
  factory PingResult.fromJson(Map<String, dynamic> json) {
    return PingResult(
      serverId: json['serverId'] as String,
      latencyMs: json['latencyMs'] as int?,
      isSuccess: json['isSuccess'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      errorMessage: json['errorMessage'] as String?,
    );
  }

  String get displayLatency {
    if (!isSuccess) return 'Failed';
    if (latencyMs == null) return 'N/A';
    if (latencyMs! < 1000) return '${latencyMs}ms';
    return '${(latencyMs! / 1000).toStringAsFixed(1)}s';
  }

  @override
  String toString() {
    return 'PingResult(serverId: $serverId, latency: $displayLatency, success: $isSuccess)';
  }
}
