import 'package:flutter/material.dart';
import '../services/v2ray_service.dart';
import '../theme/app_theme.dart';

class ConnectionToggle extends StatelessWidget {
  final VPNConnectionStatus status;
  final bool isConnecting;
  final bool hasSelectedServer;
  final VoidCallback onToggle;

  const ConnectionToggle({
    super.key,
    required this.status,
    required this.isConnecting,
    required this.hasSelectedServer,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = status == VPNConnectionStatus.connected;
    final isProcessing = isConnecting || status == VPNConnectionStatus.connecting || status == VPNConnectionStatus.disconnecting;

    // Disabled only if:
    // 1. No server selected AND not connected
    // 2. Currently processing (loading)
    final isEnabled = (hasSelectedServer || isConnected) && !isProcessing;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minimal Divider
          Container(width: double.infinity, height: 1, color: Colors.white.withValues(alpha: 0.05)),
          const SizedBox(height: 20),

          // Toggle button
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: isEnabled ? onToggle : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? AppTheme.errorColor : Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.2),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: isProcessing
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                  : Text(
                      isConnected ? 'DISCONNECT' : (isConnecting ? 'CONNECTING...' : 'CONNECT'),
                      style: const TextStyle(fontSize: 14, letterSpacing: 1.5, fontWeight: FontWeight.w900),
                    ),
            ),
          ),
          if (!hasSelectedServer && !isConnected) ...[
            const SizedBox(height: 12),
            Text(
              'SELECT A DESTINATION TO START',
              style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ],
      ),
    );
  }
}
