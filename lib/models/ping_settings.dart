class PingSettings {
  final int chunkSize; // How many servers to ping concurrently
  final int timeoutPerPing; // Timeout for single ping (seconds)
  final int pingSize; // Size of ping packet (bytes)
  final int timeoutPerChunk; // Total timeout for chunk (seconds)
  final int retryCount; // Number of ping attempts per server

  const PingSettings({this.chunkSize = 3, this.timeoutPerPing = 5, this.pingSize = 32, this.timeoutPerChunk = 15, this.retryCount = 3});

  // Default settings
  static const PingSettings defaultSettings = PingSettings();

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'chunkSize': chunkSize,
      'timeoutPerPing': timeoutPerPing,
      'pingSize': pingSize,
      'timeoutPerChunk': timeoutPerChunk,
      'retryCount': retryCount,
    };
  }

  // Create from JSON
  factory PingSettings.fromJson(Map<String, dynamic> json) {
    return PingSettings(
      chunkSize: json['chunkSize'] as int? ?? 3,
      timeoutPerPing: json['timeoutPerPing'] as int? ?? 5,
      pingSize: json['pingSize'] as int? ?? 32,
      timeoutPerChunk: json['timeoutPerChunk'] as int? ?? 15,
      retryCount: json['retryCount'] as int? ?? 3,
    );
  }

  // Create a copy with modified values
  PingSettings copyWith({int? chunkSize, int? timeoutPerPing, int? pingSize, int? timeoutPerChunk, int? retryCount}) {
    return PingSettings(
      chunkSize: chunkSize ?? this.chunkSize,
      timeoutPerPing: timeoutPerPing ?? this.timeoutPerPing,
      pingSize: pingSize ?? this.pingSize,
      timeoutPerChunk: timeoutPerChunk ?? this.timeoutPerChunk,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  String toString() {
    return 'PingSettings(chunk: $chunkSize, timeout: ${timeoutPerPing}s, size: ${pingSize}B)';
  }
}
