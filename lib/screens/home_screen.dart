import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flaming_cherubim/theme/app_theme.dart';
import '../models/v2ray_server.dart';
import '../models/ping_result.dart';
import '../services/v2ray_service.dart';
import '../services/storage_service.dart';
import '../services/ping_service.dart';
import '../services/usage_stats_service.dart';
import '../services/ip_info_service.dart';
import '../models/ping_settings.dart';
import '../widgets/server_list_item.dart';
import '../widgets/connection_toggle.dart';
import '../widgets/ping_button.dart';
import 'add_server_screen.dart';
import 'ping_settings_screen.dart';
import 'webview_screen.dart';
import 'logs_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final V2RayService _v2rayService = V2RayService();
  final PingService _pingService = PingService();
  final UsageStatsService _usageStatsService = UsageStatsService();
  final IpInfoService _ipInfoService = IpInfoService();
  late StorageService _storageService;

  List<V2RayServer> _servers = [];
  Map<String, PingResult> _pingResults = {};
  String? _selectedServerId;
  bool _isPinging = false;
  int _pingCompleted = 0;
  int _pingTotal = 0;
  PingSettings _pingSettings = PingSettings.defaultSettings;
  String? _customDns;
  bool _proxyOnly = false;
  bool _useSystemDns = true;
  bool _showUsageStats = false;
  bool _censorAddresses = false;
  IpInfo? _ipInfo;
  UsageStats _currentStats = UsageStats(uploadBytes: 0, downloadBytes: 0, memoryMB: 0);
  StreamSubscription<VPNConnectionStatus>? _statusSubscription;
  StreamSubscription<UsageStats>? _statsSubscription;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _storageService = await StorageService.init();
    await _v2rayService.init();

    _statusSubscription = _v2rayService.statusStream.listen((status) {
      if (mounted) {
        setState(() {});

        // Auto-ping on connect/disconnect
        if (status == VPNConnectionStatus.connected || status == VPNConnectionStatus.disconnected) {
          if (_storageService.loadAutoPingEnabled()) {
            _pingAllServers();
          }
        }

        // Update both widgets on status change
        _updateWidgets(status == VPNConnectionStatus.connected);
        
        // Start/stop usage monitoring based on connection
        if (status == VPNConnectionStatus.connected && _showUsageStats) {
          _usageStatsService.startMonitoring();
        } else if (status == VPNConnectionStatus.disconnected) {
          _usageStatsService.stopMonitoring();
          setState(() => _ipInfo = null);
        }

        // Fetch IP on connect
        if (status == VPNConnectionStatus.connected) {
          Future.delayed(const Duration(seconds: 2), () async {
            final info = await _ipInfoService.fetchIpInfo();
            if (mounted && info != null) {
              setState(() => _ipInfo = info);
            }
          });
        }
      }
    });
    
    // Listen to usage stats
    _statsSubscription = _usageStatsService.statsStream.listen((stats) {
      if (mounted) {
        setState(() {
          _currentStats = stats;
        });
      }
    });

    _loadData();
  }

  // Update both rectangular and circle widgets
  Future<void> _updateWidgets(bool isConnected) async {
    const platform = MethodChannel('com.flaming.cherubim/widget');
    try {
      await platform.invokeMethod('updateWidgetState', {'is_connected': isConnected});
      await platform.invokeMethod('updateCircleWidgetState', {'is_connected': isConnected});
    } catch (e) {
      // Widget update failed, but don't interrupt flow
    }
  }

  void _loadData() {
    if (!mounted) return;
    setState(() {
      _servers = _storageService.loadServers();
      _pingResults = _storageService.loadPingResults();
      _selectedServerId = _storageService.loadSelectedServerId();
      _pingSettings = _storageService.loadPingSettings();
      _customDns = _storageService.loadCustomDns();
      _proxyOnly = _storageService.loadProxyOnly();
      _useSystemDns = _storageService.loadUseSystemDns();
      _showUsageStats = _storageService.loadShowUsageStats();
      _censorAddresses = _storageService.loadCensorAddresses();
    });
  }

  Future<void> _addServer() async {
    final result = await Navigator.push<V2RayServer>(context, MaterialPageRoute(builder: (context) => const AddServerScreen()));

    if (result != null) {
      await _storageService.addServer(result);
      _loadData();
    }
  }

  Future<void> _editServer(V2RayServer server) async {
    final result = await Navigator.push<V2RayServer>(context, MaterialPageRoute(builder: (context) => AddServerScreen(server: server)));

    if (result != null) {
      await _storageService.updateServer(result);
      _loadData();
    }
  }

  Future<void> _deleteServer(String serverId) async {
    await _storageService.removeServer(serverId);
    if (_selectedServerId == serverId) {
      _selectedServerId = null;
      await _storageService.saveSelectedServerId(null);
    }
    _loadData();
  }

  void _selectServer(String serverId) {
    setState(() {
      // If already selected, unselect it
      if (_selectedServerId == serverId) {
        _selectedServerId = null;
      } else {
        _selectedServerId = serverId;
      }
    });
    _storageService.saveSelectedServerId(_selectedServerId);
  }

  Future<void> _toggleConnection() async {
    try {
      if (_v2rayService.status == VPNConnectionStatus.connected) {
        await _v2rayService.disconnect();
      } else if (_v2rayService.status == VPNConnectionStatus.disconnected || _v2rayService.status == VPNConnectionStatus.error) {
        if (_selectedServerId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Please select a server first'),
                backgroundColor: AppTheme.accentColor,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
              ),
            );
          }
          return;
        }

        final server = _servers.firstWhere((s) => s.id == _selectedServerId);

        final success = await _v2rayService.connect(server, customDns: _customDns, proxyOnly: _proxyOnly, useSystemDns: _useSystemDns);

        if (mounted && !success) {
          // Show error dialog with details
          final errorMessage = _v2rayService.lastError ?? 'Unknown error occurred';

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Connection Failed'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(errorMessage),
                  const SizedBox(height: 16),
                  if (errorMessage.contains('permission'))
                    const Text(
                      'VPN permission is required for system-wide VPN mode. Try enabling Proxy Mode instead.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    )
                  else if (errorMessage.contains('timeout')) ...[
                    const Text(
                      'Server may be unreachable or slow. Try a different server.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const Text('Check the logs for more details.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _openLogsPage();
                  },
                  child: const Text('View Logs'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _pingAllServers() async {
    if (_servers.isEmpty) return;

    setState(() {
      _isPinging = true;
      _pingCompleted = 0;
      _pingTotal = _servers.length;
    });

    final results = await _pingService.pingAllServers(
      _servers,
      _pingSettings,
      _v2rayService, // Pass V2RayService for accurate pinging
      onProgress: (completed, total) {
        if (mounted) {
          setState(() {
            _pingCompleted = completed;
            _pingTotal = total;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _pingResults = results;
        _isPinging = false;
      });
    }

    await _storageService.savePingResults(results);
  }

  Future<void> _openPingSettings() async {
    final result = await Navigator.push<PingSettings>(
      context,
      MaterialPageRoute(builder: (context) => PingSettingsScreen(currentSettings: _pingSettings)),
    );

    if (result != null) {
      if (!mounted) return;
      setState(() {
        _pingSettings = result;
      });
      await _storageService.savePingSettings(result);
      _loadData(); // Reload to pick up custom DNS
    }
  }

  void _openWebView() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const WebViewScreen()));
  }

  void _openLogsPage() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const LogsPage()));
  }

  String _getConnectionStatusText() {
    switch (_v2rayService.status) {
      case VPNConnectionStatus.connected:
        if (_proxyOnly) {
          return 'CONNECTED (Proxy Mode - localhost:10808)';
        }
        return 'CONNECTED (VPN Mode - System-wide)';
      case VPNConnectionStatus.connecting:
        return 'CONNECTING...';
      case VPNConnectionStatus.disconnecting:
        return 'DISCONNECTING...';
      case VPNConnectionStatus.error:
        final error = _v2rayService.lastError ?? 'FAILED';
        // Truncate long error messages for status display
        final shortError = error.length > 50 ? '${error.substring(0, 47)}...' : error;
        return 'ERROR: $shortError';
      case VPNConnectionStatus.disconnected:
        return 'READY';
    }
  }

  void _showServerActions(V2RayServer server) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Connection'),
              onTap: () {
                Navigator.pop(context);
                _editServer(server);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share Connection Link'),
              onTap: () {
                Navigator.pop(context);
                _shareServerLink(server);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.errorColor),
              title: Text('Delete Server', style: TextStyle(color: AppTheme.errorColor)),
              onTap: () {
                Navigator.pop(context);
                _deleteServer(server.id);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _shareServerLink(V2RayServer server) async {
    final shareLink = server.toShareLink();
    await Clipboard.setData(ClipboardData(text: shareLink));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Connection link copied to clipboard'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppTheme.surfaceColor,
                  title: const Text('Share Link'),
                  content: SingleChildScrollView(
                    child: SelectableText(shareLink, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Flaming Cherubim', style: TextStyle(letterSpacing: 2, fontSize: 20, fontWeight: FontWeight.w900)),
            Row(
              children: [
                if (_v2rayService.status == VPNConnectionStatus.connecting) ...[
                  const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 8),
                ],
                if (_v2rayService.status == VPNConnectionStatus.connected) ...[
                  // IP & Flag
                  if (_ipInfo != null) ...[
                      Text(
                        '${_ipInfo!.flagEmoji} ${_censorAddresses ? _censorString(_ipInfo!.ip) : _ipInfo!.ip}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                      ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.2)),
                    const SizedBox(width: 12),
                  ],

                  // Usage Stats or Mode
                  if (_showUsageStats)
                    Row(
                      children: [
                        Icon(Icons.arrow_upward, size: 10, color: Colors.white.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(
                          _currentStats.uploadFormatted,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_downward, size: 10, color: Colors.white.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(
                          _currentStats.downloadFormatted,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                        ),
                      ],
                    )
                  else
                    Text(
                      _proxyOnly ? 'PROXY LOCALHOST:10808' : 'SYSTEM TUNNEL',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.successColor.withValues(alpha: 0.8),
                      ),
                    ),
                ] else
                  Text(
                    _getConnectionStatusText(),
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          PingButton(isPinging: _isPinging, completedCount: _pingCompleted, totalCount: _pingTotal, onPressed: _pingAllServers),
          IconButton(icon: const Icon(Icons.tune, size: 20), onPressed: _openPingSettings, tooltip: 'Ping Settings'),
          IconButton(icon: const Icon(Icons.description_outlined, size: 20), onPressed: _openLogsPage, tooltip: 'View Logs'),
          IconButton(icon: const Icon(Icons.public, size: 20), onPressed: _openWebView, tooltip: 'Open Browser'),
        ],
      ),
      body: Column(
        children: [
          _buildProxyToggle(),
          Expanded(child: _buildServerList()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: ConnectionToggle(
          status: _v2rayService.status,
          isConnecting: false, // Managed by status
          hasSelectedServer: _selectedServerId != null,
          onToggle: _toggleConnection,
        ),
      ),
    );
  }

  Widget _buildServerList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 0, bottom: 20),
      itemCount: _servers.length + 1,
      itemBuilder: (context, index) {
        // Add Server Tile at the end
        if (index == _servers.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            child: InkWell(
              onTap: _addServer,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1, style: BorderStyle.solid),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline, color: Colors.white.withValues(alpha: 0.3), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'ADD NEW DESTINATION',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final server = _servers[index];
        final pingResult = _pingResults[server.id];
        final isSelected = server.id == _selectedServerId;

        return ServerListItem(
          server: server,
          pingResult: pingResult,
          isSelected: isSelected,
          onTap: () => _selectServer(server.id),
          onLongPress: () => _showServerActions(server),
          onDelete: () => _deleteServer(server.id),
          censorAddress: _censorAddresses,
        );
      },
    );
  }

  Widget _buildProxyToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(_proxyOnly ? Icons.alt_route : Icons.vpn_lock, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _proxyOnly ? 'PROXY ONLY MODE' : 'SYSTEM VPN MODE',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                  ),
                  Text(
                    _proxyOnly ? 'No TUN interface, only local proxy' : 'VPN tunnel for entire device',
                    style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ],
              ),
            ],
          ),
          Switch(
            value: _proxyOnly,
            onChanged: (value) async {
              setState(() {
                _proxyOnly = value;
              });
              await _storageService.saveProxyOnly(value);
            },
            activeThumbColor: AppTheme.accentColor,
            activeTrackColor: AppTheme.accentColor.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  String _censorString(String input) {
    if (input.length <= 8) return input;
    return '${input.substring(0, 4)}***${input.substring(input.length - 4)}';
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statsSubscription?.cancel();
    _usageStatsService.dispose();
    _v2rayService.dispose();
    super.dispose();
  }
}
