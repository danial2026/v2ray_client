import 'dart:async';
import 'dart:io';
import '../models/v2ray_server.dart';
import '../models/ping_result.dart';
import '../models/ping_settings.dart';

import '../services/v2ray_service.dart';

class PingService {
  // Ping a single server using V2Ray core (TCP/Http ping) if provider available
  // Fallback to ICMP if no provider (though V2RayService should always be provided)
  Future<PingResult> pingServer(V2RayServer server, PingSettings settings, [dynamic provider]) async {
    // If provider is V2RayService, use it for real V2Ray ping
    if (provider is V2RayService) {
      try {
        final delay = await provider.getServerDelay(server);
        if (delay != null && delay > 0) {
          return PingResult.success(serverId: server.id, latencyMs: delay);
        } else {
          return PingResult.failure(serverId: server.id, errorMessage: 'Timeout');
        }
      } catch (e) {
        return PingResult.failure(serverId: server.id, errorMessage: e.toString());
      }
    }

    final address = server.address;

    try {
      // Use system ping command
      // -c 1: one packet
      // -W 2: 2 seconds timeout
      // Note: On some Android devices, the binary might be in /system/bin/ping
      final result = await Process.run('ping', ['-c', '1', '-W', '2', address]).timeout(const Duration(seconds: 3));

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Parse latency from output e.g. "time=45.2 ms"
        final match = RegExp(r'time=([\d.]+)\s*ms').firstMatch(output);
        if (match != null) {
          final latency = double.parse(match.group(1)!).round();
          return PingResult.success(serverId: server.id, latencyMs: latency);
        }
      }

      // Fallback message if ping command is not found or fails
      return PingResult.failure(serverId: server.id, errorMessage: 'Ping failed (Exit: ${result.exitCode})');
    } catch (e) {
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
