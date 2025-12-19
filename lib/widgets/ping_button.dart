import 'package:flutter/material.dart';

class PingButton extends StatelessWidget {
  final bool isPinging;
  final int? completedCount;
  final int? totalCount;
  final VoidCallback onPressed;

  const PingButton({super.key, required this.isPinging, this.completedCount, this.totalCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: isPinging ? null : onPressed,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          if (isPinging)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            )
          else
            const Icon(Icons.network_ping, size: 24),
        ],
      ),
      tooltip: isPinging ? 'Pinging servers... ($completedCount/$totalCount)' : 'Ping all servers',
    );
  }
}
