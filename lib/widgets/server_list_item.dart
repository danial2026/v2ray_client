import 'package:flutter/material.dart';
import '../models/v2ray_server.dart';
import '../models/ping_result.dart';
import '../theme/app_theme.dart';

class ServerListItem extends StatelessWidget {
  final V2RayServer server;
  final PingResult? pingResult;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback? onShare;
  final bool censorAddress;

  const ServerListItem({
    super.key,
    required this.server,
    this.pingResult,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    this.onShare,
    this.censorAddress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Minimal Selection Indicator
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 16),

              // Server Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      censorAddress 
                          ? '${server.protocol.toUpperCase()} • ${_censorString(server.address)}'
                          : '${server.protocol.toUpperCase()} • ${server.address}',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Ping Result
              if (pingResult != null) _buildPingBadge(),

              // Delete Action (Subtle)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDelete,
                color: Colors.white.withValues(alpha: 0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPingBadge() {
    final Color color;
    if (pingResult == null || !pingResult!.isSuccess) {
      color = AppTheme.errorColor;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: const Text(
          'FAIL',
          style: TextStyle(color: AppTheme.errorColor, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      );
    }

    final latencyMs = pingResult!.latencyMs!;
    color = AppTheme.pingLatencyColor(latencyMs);

    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        '${pingResult!.latencyMs}ms',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _censorString(String input) {
    if (input.length <= 8) return input;
    return '${input.substring(0, 4)}***${input.substring(input.length - 4)}';
  }
}
