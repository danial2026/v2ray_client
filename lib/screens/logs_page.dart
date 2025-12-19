import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';
import '../theme/app_theme.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  late final LoggerService _loggerService;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _loggerService = LoggerService();

    // Listen for new logs and scroll to bottom
    _loggerService.logsStream.listen((_) {
      if (_autoScroll && mounted) {
        _scrollToBottom();
      }
    });

    // Initial scroll after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && mounted) {
        _scrollToBottom(immediate: true);
      }
    });
  }

  void _scrollToBottom({bool immediate = false}) {
    Future.delayed(Duration(milliseconds: immediate ? 0 : 100), () {
      if (_scrollController.hasClients) {
        if (immediate) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'ERROR':
        return AppTheme.errorColor;
      case 'WARNING':
        return Colors.orange;
      case 'DEBUG':
        return Colors.grey;
      default:
        return Colors.white.withValues(alpha: 0.7);
    }
  }

  void _copyLogsToClipboard() {
    final allLogs = _loggerService.getAllLogsAsString();
    Clipboard.setData(ClipboardData(text: allLogs)).then((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard'), duration: Duration(seconds: 2)));
    });
  }

  void _copySingleLogToClipboard(String message) {
    Clipboard.setData(ClipboardData(text: message)).then((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Log message copied to clipboard'),
          backgroundColor: AppTheme.accentColor.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          width: 250,
        ),
      );
    });
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Clear Logs'),
        content: const Text('Are you sure you want to clear all logs?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _loggerService.clearLogs();
              Navigator.pop(context);
              if (mounted) setState(() {});
            },
            child: Text('Clear', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Logs'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.content_copy, size: 20), onPressed: _copyLogsToClipboard, tooltip: 'Copy all logs'),
          IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: _clearLogs, tooltip: 'Clear logs'),
        ],
      ),
      body: StreamBuilder<dynamic>(
        stream: _loggerService.logsStream,
        builder: (context, snapshot) {
          final logs = _loggerService.logs;

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description_outlined, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text('No logs yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16)),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Log count and auto-scroll toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${logs.length} log${logs.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w500),
                    ),
                    Row(
                      children: [
                        Text('Auto-scroll', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
                        const SizedBox(width: 8),
                        Switch(
                          value: _autoScroll,
                          onChanged: (value) {
                            setState(() => _autoScroll = value);
                          },
                          activeThumbColor: AppTheme.accentColor,
                          activeTrackColor: AppTheme.accentColor.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Logs list
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final levelColor = _getLevelColor(log.level);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onLongPress: () => _copySingleLogToClipboard(log.message),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: levelColor.withValues(alpha: 0.1), width: 0.5),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Time
                                Text(
                                  log.formattedTime,
                                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4), fontFamily: 'monospace'),
                                ),
                                const SizedBox(width: 12),
                                // Level badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: levelColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: levelColor.withValues(alpha: 0.3), width: 0.5),
                                  ),
                                  child: Text(
                                    log.level,
                                    style: TextStyle(fontSize: 9, color: levelColor, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Message
                                Expanded(
                                  child: Text(
                                    log.message,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withValues(alpha: 0.8),
                                      height: 1.4,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: null,
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
