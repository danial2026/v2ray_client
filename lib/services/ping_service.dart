import 'dart:async';
import 'dart:io';
import '../models/v2ray_server.dart';
import '../models/ping_result.dart';
import '../models/ping_settings.dart';

import '../services/v2ray_service.dart';
import '../services/logger_service.dart';

class PingService {
  final LoggerService _logger = LoggerService();

  // Ping a single server using V2Ray core (TCP/Http ping) if provider available
  // Fallback to ICMP if no provider (though V2RayService should always be provided)
  Future<PingResult> pingServer(V2RayServer server, PingSettings settings, [dynamic provider]) async {
    _logger.info('Pinging server: ${server.name} (${server.address}:${server.port})');
    
    // If provider is V2RayService, use it for real V2Ray ping
    if (provider is V2RayService) {
      try {
        final delay = await provider.getServerDelay(server);
        if (delay != null && delay > 0) {
          _logger.info('✓ Server ${server.name} responded in ${delay}ms');
          return PingResult.success(serverId: server.id, latencyMs: delay);
        } else {
          _logger.warning('✗ Server ${server.name} ping timeout or unreachable');
          return PingResult.failure(serverId: server.id, errorMessage: 'Timeout');
        }
      } catch (e, stackTrace) {
        _logger.error('✗ Server ${server.name} ping failed: $e', stackTrace: stackTrace);
        return PingResult.failure(serverId: server.id, errorMessage: e.toString());
      }
    }

    final address = server.address;

    try {
      // Use system ping command
      // -c 1: one packet
      // -W 3000: 3000ms on macOS, 3000s on Linux. 
      // We rely on Dart's .timeout() to enforce the actual ~3s limit cross-platform.
      _logger.debug('Using system ping for ${server.name} at $address');
      final result = await Process.run('ping', ['-c', '1', '-W', '3000', address]).timeout(const Duration(seconds: 3));

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // 1. Try generic output: "time=45.2 ms"
        var match = RegExp(r'time=([\d.]+)\s*ms').firstMatch(output);
        if (match != null) {
          final latency = double.parse(match.group(1)!).round();
          _logger.info('✓ Server ${server.name} ICMP ping: ${latency}ms');
          return PingResult.success(serverId: server.id, latencyMs: latency);
        }

        // 2. Try summary line: "min/avg/max/stddev = 45.200/45.200/..."
        match = RegExp(r'min/avg/max/stddev = [\d.]+/([\d.]+)/').firstMatch(output);
        if (match != null) {
          final latency = double.parse(match.group(1)!).round();
          _logger.info('✓ Server ${server.name} ICMP ping (stats): ${latency}ms');
          return PingResult.success(serverId: server.id, latencyMs: latency);
        }

        _logger.warning('Ping output parse failed for ${server.name}. Output: "${output.trim()}"');
      }

      // Fallback message if ping command is not found or fails
      _logger.warning('✗ Server ${server.name} ping failed with exit code: ${result.exitCode}');
      return PingResult.failure(serverId: server.id, errorMessage: 'Ping failed (Exit: ${result.exitCode})');
    } on TimeoutException catch (e) {
      _logger.warning('✗ Server ${server.name} ping timeout after 3 seconds');
      return PingResult.failure(serverId: server.id, errorMessage: 'Timeout: ${e.toString()}');
    } catch (e, stackTrace) {
      _logger.error('✗ Server ${server.name} network error: $e', stackTrace: stackTrace);
      return PingResult.failure(serverId: server.id, errorMessage: 'Error: ${e.toString()}');
    }
  }

  // Ping all servers sequentially using real ICMP ping
  Future<Map<String, PingResult>> pingAllServers(
    List<V2RayServer> servers,
    PingSettings settings,
    dynamic provider, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <String, PingResult>{};
    final totalServers = servers.length;
    int completedServers = 0;

    for (final server in servers) {
      final result = await pingServer(server, settings);
      results[server.id] = result;

      completedServers++;
      if (onProgress != null) {
        onProgress(completedServers, totalServers);
      }

      // Small cooling delay to prevent UI jitter
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return results;
  }

  // Cancel ongoing ping operations
  void cancelPing() {
    // Implementation for cancellation if needed
  }
}
