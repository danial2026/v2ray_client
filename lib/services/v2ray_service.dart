import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:v2ray_dan/v2ray_dan.dart';
import '../models/v2ray_server.dart';
import '../models/proxy_mode.dart';
import 'logger_service.dart';
import 'storage_service.dart';

enum VPNConnectionStatus { disconnected, connecting, connected, disconnecting, error }

class V2RayService {
  static final V2RayService _instance = V2RayService._internal();
  factory V2RayService() => _instance;

  late final V2ray _v2rayPlugin;
  late final LoggerService _logger;
  StorageService? _storage;

  VPNConnectionStatus _status = VPNConnectionStatus.disconnected;
  V2RayServer? _currentServer;
  String? _lastError;
  String? _filesDir;
  bool _isInitialized = false;
  Timer? _logPollingTimer;
  bool _isConnectInProgress = false;
  ProxyMode _proxyMode = ProxyMode.socks; // Default to SOCKS

  VPNConnectionStatus get status => _status;
  V2RayServer? get currentServer => _currentServer;
  String? get lastError => _lastError;

  // Stream for status changes
  final StreamController<VPNConnectionStatus> _statusController = StreamController<VPNConnectionStatus>.broadcast();
  Stream<VPNConnectionStatus> get statusStream => _statusController.stream;

  V2RayService._internal() {
    _logger = LoggerService();
    _v2rayPlugin = V2ray(
      onStatusChanged: (status) {
        final newStatus = _mapPluginStatus(status.state);
        if (_status != newStatus) {
          _status = newStatus;
          _logger.info('Native Status Broadcast: ${status.state} -> $newStatus');
          _statusController.add(_status);
        }
      },
    );
    _logger.info('V2RayService Singleton initialized');
    _setupAndroidLogReceiver();
  }

  // Setup receiver for Android/Kotlin logs
  void _setupAndroidLogReceiver() {
    try {
      // Use the plugin's MethodChannel name
      const platform = MethodChannel('com.flaming.cherubim/logs');

      platform.setMethodCallHandler((call) async {
        if (call.method == 'log') {
          final level = call.arguments['level'] as String?;
          final message = call.arguments['message'] as String?;

          if (message != null) {
            // Forward Android logs to Flutter logger
            switch (level) {
              case 'ERROR':
                _logger.error(message);
                break;
              case 'WARN':
                _logger.warning(message);
                break;
              case 'DEBUG':
                _logger.debug(message);
                break;
              default:
                _logger.info(message);
            }
          }
        }
      });

      _logger.info('✓ Android log receiver setup complete');
    } catch (e) {
      _logger.warning('Failed to setup Android log receiver: $e');
    }
  }

  VPNConnectionStatus _mapPluginStatus(String state) {
    switch (state.toLowerCase()) {
      case 'connected':
        return VPNConnectionStatus.connected;
      case 'connecting':
        return VPNConnectionStatus.connecting;
      case 'disconnecting':
        return VPNConnectionStatus.disconnecting;
      case 'disconnected':
        return VPNConnectionStatus.disconnected;
      case 'error':
        return VPNConnectionStatus.error;
      default:
        return VPNConnectionStatus.disconnected;
    }
  }

  // Initialize V2Ray core
  Future<void> init() async {
    if (_isInitialized) {
      _logger.info('V2Ray core already initialized, skipping...');
      return;
    }

    try {
      _logger.info('========== Initializing V2Ray Core ==========');

      // CRITICAL: Initialize the V2Ray plugin before first use
      // This is required by flutter_v2ray_client and sets up the native services
      _logger.info('Calling v2ray.initialize()...');
      try {
        _filesDir = await _v2rayPlugin
            .initialize(notificationIconResourceType: 'drawable', notificationIconResourceName: 'ic_stat_v2ray')
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException('V2Ray initialization timed out');
              },
            );
        _logger.info('V2Ray plugin initialized successfully');
        _logger.info('App files directory: $_filesDir');
      } catch (e, stackTrace) {
        _logger.error('FATAL: V2Ray plugin initialization failed: $e', stackTrace: stackTrace);
        throw Exception('Failed to initialize V2Ray plugin: $e');
      }

      // Verify plugin is working by getting core version
      _logger.info('Verifying V2Ray core is responsive...');
      try {
        final version = await _v2rayPlugin.getCoreVersion().timeout(const Duration(seconds: 3), onTimeout: () => '');
        if (version != null && version.isNotEmpty) {
          _logger.info('✓ V2Ray core version: $version');
        } else {
          _logger.warning('Could not retrieve core version (may not be critical)');
        }
      } catch (e) {
        _logger.warning('Core version check failed (non-fatal): $e');
      }

      _isInitialized = true;
      _logger.info('========== V2Ray initialization complete ==========');
    } catch (e, stackTrace) {
      _lastError = 'Failed to initialize V2Ray: $e';
      _status = VPNConnectionStatus.error;
      _logger.error(_lastError!, stackTrace: stackTrace);
      _statusController.add(_status);
      rethrow; // Re-throw so the app knows initialization failed
    }
  }

  // Check for VPN permission
  Future<bool> checkPermission() async {
    _logger.info('Checking VPN permission...');
    try {
      final hasPermission = await _v2rayPlugin.requestPermission().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logger.error('VPN permission request timed out');
          return false;
        },
      );

      _logger.info('VPN permission status: ${hasPermission ? "granted" : "denied"}');
      return hasPermission;
    } catch (e, stackTrace) {
      _logger.error('VPN permission check failed: $e', stackTrace: stackTrace);
      return false;
    }
  }

  // Full System Reset
  Future<void> fullSystemReset() async {
    _logger.warning('========== INITIATING FULL SYSTEM RESET ==========');

    // Force stop V2Ray
    try {
      await _v2rayPlugin.stopV2Ray();
    } catch (e) {
      _logger.error('Reset: Failed to stop V2Ray (ignoring): $e');
    }

    // Clear internal state
    _status = VPNConnectionStatus.disconnected;
    _currentServer = null;
    _lastError = null;
    _statusController.add(_status);

    // Clear storage data (optional but recommended for full reset, but user asked for "reset vpn for device")
    // Let's just reset the VPN state for now, as clearing all data might be too aggressive unless explicitly asked.
    // However, the prompt says "reset vpn for device and also relaunch the app".

    _logger.warning('========== SYSTEM RESET COMPLETE ==========');

    // Force App Exit (User must manually relaunch)
    // Using exit(0) is drastic but requested.
    exit(0);
  }

  // Connect to a V2Ray server
  Future<bool> connect(
    V2RayServer server, {
    String? customDns,
    bool proxyOnly = false,
    bool useSystemDns = true,
    ProxyMode? proxyMode,
  }) async {
    _logger.info('========== Starting connection process ==========');
    _logger.info('Mode: ${proxyOnly ? "Proxy Only" : "VPN (System-wide)"}');
    _logger.info('Server: ${server.name} (${server.address}:${server.port})');
    _logger.info('Protocol: ${server.protocol}');

    // Set proxy mode (with default)
    _proxyMode = proxyMode ?? ProxyMode.socks;
    _logger.info('Proxy Mode: ${_proxyMode.displayName}');

    // Platform validation
    if (!Platform.isAndroid && !Platform.isMacOS) {
      _logger.error('Unsupported platform: ${Platform.operatingSystem}');
      _cleanupAfterError('Flaming Cherubim currently only supports VPN connections on Android and macOS.');
      return false;
    }


    try {
      // Use a slightly longer timeout to prevent premature "stuck" declarations
      return await _runConnectLogic(server, customDns, proxyOnly, useSystemDns).timeout(
        const Duration(seconds: 45), // Increased timeout to allow for macOS admin prompt interaction
        onTimeout: () {
          _logger.error('Connection logic timed out after 45 seconds');
          // Don't throw - try to clean up and return false to keep UI alive
          _cleanupAfterError('Connection timed out');
          return false;
        },
      );
    } catch (e, stackTrace) {
      _logger.error('========== Connection failed ==========');
      _logger.error('Error: $e', stackTrace: stackTrace);
      _cleanupAfterError('Connection error: $e');
      return false;
    }
  }

  Future<void> _cleanupAfterError(String errorMsg) async {
    _status = VPNConnectionStatus.error;
    _lastError = errorMsg;
    _currentServer = null;
    _statusController.add(_status);

    // Try to cleanup any partial connection
    try {
      _logger.info('Attempting cleanup after failed connection...');
      await _v2rayPlugin.stopV2Ray();
    } catch (cleanupError) {
      _logger.warning('Cleanup failed (non-fatal): $cleanupError');
    }
  }

  Future<bool> _runConnectLogic(V2RayServer server, String? customDns, bool proxyOnly, bool useSystemDns) async {
    // Guard against concurrent connection attempts
    if (_isConnectInProgress) {
      throw Exception('Connection already in progress, please wait');
    }
    _isConnectInProgress = true;
    
    try {
      return await _runConnectLogicInternal(server, customDns, proxyOnly, useSystemDns);
    } finally {
      _isConnectInProgress = false;
    }
  }

  Future<bool> _runConnectLogicInternal(V2RayServer server, String? customDns, bool proxyOnly, bool useSystemDns) async {
    // Step 1: Force reset existing connections
    _logger.info('Ensuring previous connections are closed...');
    try {
      // Unconditionally disconnect to ensure clean state
      // We don't check _status here because it might be out of sync with native side
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _logger.warning('Reset warning (non-fatal): $e');
      // Continue anyway as we want to try connecting
    }

    // Step 2: Update status to connecting
    _logger.info('Step 1/7: Updating status to CONNECTING');
    _status = VPNConnectionStatus.connecting;
    _statusController.add(_status);
    _currentServer = server;
    _lastError = null;

    // Step 3: Check VPN permission for VPN mode
    if (!proxyOnly) {
      _logger.info('Step 2/7: Checking VPN permission...');
      try {
        final hasPermission = await _v2rayPlugin.requestPermission();
        _logger.info('VPN Permission granted: $hasPermission');

        if (!hasPermission) {
          throw Exception('VPN permission denied by user. Cannot establish VPN connection.');
        }
      } catch (e, stackTrace) {
        _logger.error('VPN permission check failed: $e', stackTrace: stackTrace);
        throw Exception('VPN permission error: $e');
      }
    } else {
      _logger.info('Step 2/7: Skipping VPN permission (proxy-only mode)');
    }

    // Step 4: Generate V2Ray configuration manually
    // Since we are using local v2ray_dan package with stub parser, we use manual config
    _logger.info('Step 3/7: Generating V2Ray configuration manually...');

    String configJson;
    try {
      final config = server.toV2RayConfig(customDns: customDns?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());

      config['inbounds'] = [
        {
          'tag': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          },
          'settings': {'auth': 'noauth', 'udp': true},
        },
        {
          'tag': 'http',
          'port': 10809,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          },
        },
      ];

      config['routing'] = {
        'domainStrategy': 'IPOnDemand',
        'rules': [
          {'type': 'field', 'outboundTag': 'proxy', 'network': 'tcp,udp'},
        ],
      };

      config['log'] = {'loglevel': 'info', 'access': 'none', 'error': 'none'};

      configJson = json.encode(config);

      // Inject core settings that might be missing from the stub generator
      final Map<String, dynamic> fullConfig = json.decode(configJson);

      // Ensure log level is correct and enable file logs in private storage
      fullConfig['log'] = {
        'loglevel': 'info',
        'access': _filesDir != null ? '$_filesDir/access.log' : 'none',
        'error': _filesDir != null ? '$_filesDir/error.log' : 'none',
      };

      // Ensure inbounds are correct for VPN mode
      // Change tags to avoid conflict with 'proxy' outbound tag
      fullConfig['inbounds'] = [
        {
          "tag": "socks-in",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"],
          },
          "settings": {"auth": "noauth", "udp": true},
        },
        {
          "tag": "http-in",
          "port": 10809,
          "listen": "127.0.0.1",
          "protocol": "http",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"],
          },
        },
      ];

      // Ensure we have direct and dns outbounds
      if (fullConfig['outbounds'] == null) fullConfig['outbounds'] = [];
      List<dynamic> outboundsList = fullConfig['outbounds'];

      if (!outboundsList.any((o) => o['tag'] == 'direct')) {
        outboundsList.add({'tag': 'direct', 'protocol': 'freedom', 'settings': {}});
      }
      if (!outboundsList.any((o) => o['tag'] == 'dns-out')) {
        outboundsList.add({'tag': 'dns-out', 'protocol': 'dns', 'settings': {}});
      }

      // DNS Configuration - Fetch system DNS dynamically
      _logger.info('Step 4/7: Fetching system DNS...');
      List<String> systemDnsServers = [];
      try {
        systemDnsServers = await _v2rayPlugin.getSystemDns();
        _logger.info('Device DNS servers: $systemDnsServers');
      } catch (e) {
        _logger.warning('Failed to fetch system DNS, will use fallback: $e');
      }

      // Resolve Server IP for bypass rule and outbound
      _logger.info('Step 5/7: Resolving server IP...');
      String resolvedIp = server.address;
      bool isIp = RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(server.address);

      if (!isIp) {
        try {
          final addresses = await InternetAddress.lookup(server.address);
          if (addresses.isNotEmpty) {
            resolvedIp = addresses.first.address;
            _logger.info('Cloud domain ${server.address} resolved to $resolvedIp');
          }
        } catch (e) {
          _logger.warning('DNS lookup failed for ${server.address}: $e');
        }
      }

      // IMPORTANT: Use the resolved IP in the outbound settings to avoid redundant lookups
      // and potential circular routing issues within the tunnel.
      if (fullConfig['outbounds'] != null && fullConfig['outbounds'].isNotEmpty) {
        for (var outbound in fullConfig['outbounds']) {
          if (outbound['tag'] == 'proxy' && outbound['settings'] != null && outbound['settings']['vnext'] != null) {
            outbound['settings']['vnext'][0]['address'] = resolvedIp;
            _logger.info('Updated outbound address to resolved IP: $resolvedIp');
          }
        }
      }

      // Prioritize Custom DNS if available
      final List<String> effectiveDns = [];
      if (customDns != null && customDns.isNotEmpty) {
        effectiveDns.addAll(customDns.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
        _logger.info('Using Custom DNS: $effectiveDns');
      } 
      
      // If no custom DNS, or if we want to append system DNS as fallback (optional strategy)
      // For privacy/leak protection, usually we prefer Custom DNS ONLY if specified.
      if (effectiveDns.isEmpty) {
        if (systemDnsServers.isNotEmpty) {
           effectiveDns.addAll(systemDnsServers);
        } else {
           effectiveDns.addAll(["8.8.8.8", "1.1.1.1"]);
        }
        _logger.info('Using System/Default DNS: $effectiveDns');
      }

      fullConfig['dns'] = {
        "servers": [...effectiveDns, "localhost"], // localhost is needed for internal routing sometimes
        "queryStrategy": "UseIP",
      };

      // Routing Strategy - Robust rules
      fullConfig['routing'] = {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          // Rule 1: Hijack all DNS traffic to dns-out (CRITICAL)
          {"type": "field", "port": 53, "outboundTag": "dns-out"},
          // Rule 2: Bypass server address to prevent absolute deadlock
          {
            "type": "field",
            "ip": [resolvedIp],
            "outboundTag": "direct",
          },
          // If it was a domain, also bypass the domain itself
          if (!isIp)
            {
              "type": "field",
              "domain": [server.address],
              "outboundTag": "direct",
            },
          // Rule 3: Bypass local network traffic
          {
            "type": "field",
            "ip": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "::1/128", "fc00::/7", "fe80::/10"],
            "outboundTag": "direct",
          },
          // Rule 4: Bypass DNS servers to prevent resolution deadlock
          {
            "type": "field",
            "ip": systemDnsServers.isNotEmpty ? systemDnsServers : ["8.8.8.8", "1.1.1.1", "1.0.0.1", "8.8.4.4"],
            "outboundTag": "direct",
          },
          // Rule 5: Hijack inbound traffic to proxy
          {
            "type": "field",
            "inboundTag": ["socks-in", "http-in"],
            "outboundTag": "proxy",
          },
          // Rule 6: Final catch-all for anything else from local/TUN
          {"type": "field", "network": "tcp,udp", "outboundTag": "proxy"},
        ],
      };

      // Re-encode
      configJson = json.encode(fullConfig);

      _logger.info('Config refined successfully - Length: ${configJson.length} bytes');
      _logger.logObject('V2Ray Final Config', fullConfig);
    } catch (e, stackTrace) {
      _logger.error('Failed to generate config: $e', stackTrace: stackTrace);
      throw Exception('Config generation failed: $e');
    }

    _logger.info('Step 5/7: Starting V2Ray core...');
    final startTime = DateTime.now();

    try {
      await _v2rayPlugin
          .startV2Ray(
            remark: server.name,
            config: configJson,
            proxyOnly: proxyOnly,
            useSystemDns: useSystemDns,
            bypassSubnets: [],
            blockedApps: null,
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              _logger.error('V2Ray startup timed out after 20 seconds');
              throw TimeoutException('V2Ray startup timeout - server may be unreachable');
            },
          );

      final startDuration = DateTime.now().difference(startTime);
      _logger.info('V2Ray core started successfully in ${startDuration.inMilliseconds}ms');
    } catch (e, stackTrace) {
      _logger.error('Failed to start V2Ray core: $e', stackTrace: stackTrace);
      throw Exception('V2Ray startup failed: $e');
    }

    // Step 7: Wait for core initialization and verify connection
    _logger.info('Step 6/7: Waiting for core initialization...');
    await Future.delayed(const Duration(milliseconds: 2000));

    // Verify connection status
    _logger.info('Step 7/7: Verifying V2Ray core is responsive...');

    // Verify core version (confirms V2Ray is responsive)
    try {
      final coreVersion = await _v2rayPlugin.getCoreVersion().timeout(const Duration(seconds: 3), onTimeout: () => '');

      if (coreVersion != null && coreVersion.isNotEmpty) {
        _logger.info('✓ V2Ray core is responsive. Version: $coreVersion');
      } else {
        _logger.warning('Could not verify core version, but continuing...');
      }
    } catch (e) {
      _logger.warning('Core verification failed (non-fatal): $e');
    }

    _logger.info('Connection verification complete');
    _logger.info('Note: Monitor app logs and test actual traffic to confirm routing.');

    // Update status to connected
    if (_status != VPNConnectionStatus.connected) {
      _logger.info('Updating status to CONNECTED');
      _status = VPNConnectionStatus.connected;
      _statusController.add(_status);
    }

    _logger.info('========== Connection successful ==========');
    _logger.info('Server: ${server.name}');
    _logger.info('Mode: ${proxyOnly ? "Proxy (use localhost:10808)" : "VPN (system-wide)"}');

    if (proxyOnly) {
      _logger.info('Configure your apps to use:');
      _logger.info('  - SOCKS5: 127.0.0.1:10808');
      _logger.info('  - HTTP: 127.0.0.1:10809');
    }

    // On macOS, automatically enable system proxy based on selected mode
    if (Platform.isMacOS) {
      _logger.info('Enabling macOS system proxy (${_proxyMode.displayName} mode)...');
      await setSystemProxy(_proxyMode);
    }

    // POST-CONNECTION DIAGNOSTICS
    _logger.info('========== Post-Connection Diagnostics ==========');
    await _runPostConnectionDiagnostics();

    // Start polling for "per request" logs from the native log files
    _startLogPolling();

    return true;
  }

  // Disconnect from V2Ray server
  Future<void> disconnect() async {
    _logger.info('========== Starting disconnection process ==========');
    _logger.info('Disconnecting from: ${_currentServer?.name ?? "VPN"}');

    try {
      _status = VPNConnectionStatus.disconnecting;
      _statusController.add(_status);

      // Stop log polling
      _stopLogPolling();

      _logger.info('Stopping V2Ray core...');
      final stopTime = DateTime.now();

      try {
        await _v2rayPlugin.stopV2Ray().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _logger.warning('Stop V2Ray timed out after 10 seconds');
            throw TimeoutException('Disconnect timeout');
          },
        );

        final stopDuration = DateTime.now().difference(stopTime);
        _logger.info('V2Ray core stopped in ${stopDuration.inMilliseconds}ms');
      } catch (e, stackTrace) {
        _logger.error('Failed to stop V2Ray cleanly: $e', stackTrace: stackTrace);
        // Continue to cleanup state even if stop failed
      }

      // On macOS, clear system proxy
      if (Platform.isMacOS) {
        await clearSystemProxy();
      }

      // Increased delay to allow network stack to fully reset
      await Future.delayed(const Duration(milliseconds: 800));

      _status = VPNConnectionStatus.disconnected;
      _statusController.add(_status);
      _currentServer = null;
      _lastError = null;

      _logger.info('========== Disconnection complete ==========');
    } catch (e, stackTrace) {
      _logger.error('========== Disconnection failed ==========');
      _logger.error('Error: $e', stackTrace: stackTrace);

      _status = VPNConnectionStatus.error;
      _lastError = 'Disconnect error: $e';
      _statusController.add(_status);

      // Force cleanup state anyway
      _currentServer = null;
    }
  }

  // Get connection status
  Future<bool> isConnected() async {
    // New package might not have getConnectedServerDelay, or it might be different
    // We rely on internal status for now
    return _status == VPNConnectionStatus.connected;
  }

  // Get server delay (ping)
  Future<int?> getServerDelay(V2RayServer server, {String? customDns}) async {
    try {
      final config = server.toV2RayConfig(customDns: customDns?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
      final configJson = json.encode(config);

      return await _v2rayPlugin.getServerDelay(config: configJson, url: 'https://www.google.com/generate_204');
    } catch (e) {
      return null;
    }
  }

  // macOS System Proxy Control
  Future<bool> setSystemProxy(ProxyMode mode) async {
    if (!Platform.isMacOS) {
      _logger.warning('System proxy control is only available on macOS');
      return false;
    }

    try {
      _logger.info('Enabling macOS system proxy (${mode.displayName} mode)...');
      
      // Call native method with proxy mode argument
      const platform = MethodChannel('v2ray_dan');
      final result = await platform.invokeMethod('setSystemProxy', {
        'proxyMode': mode.name,
      });
      
      if (result == true) {
        _logger.info('✓ System proxy enabled successfully');
      } else {
        _logger.warning('Failed to enable system proxy (may need admin permissions)');
      }
      return result == true;
    } catch (e) {
      _logger.error('Error enabling system proxy: $e');
      return false;
    }
  }

  Future<bool> clearSystemProxy() async {
    if (!Platform.isMacOS) {
      return false;
    }

    try {
      _logger.info('Disabling macOS system proxy...');
      final result = await _v2rayPlugin.clearSystemProxy();
      if (result) {
        _logger.info('✓ System proxy disabled successfully');
      } else {
        _logger.warning('Failed to disable system proxy');
      }
      return result;
    } catch (e) {
      _logger.error('Error disabling system proxy: $e');
      return false;
    }
  }

  // Parse vmess:// or vless:// link
  Future<V2RayServer?> parseVmessLink(String link) async {
    try {
      return V2RayServer.fromAnyLink(link);
    } catch (e) {
      _lastError = 'Failed to parse link: $e';
      return null;
    }
  }

  // Run post-connection diagnostics
  Future<void> _runPostConnectionDiagnostics() async {
    try {
      _logger.info('Running post-connection diagnostics...');

      // Wait a bit for V2Ray to stabilize
      await Future.delayed(const Duration(seconds: 2));

      // Diagnostic 1: Check V2Ray core logs
      _logger.info('Diagnostic 1/3: Fetching V2Ray core logs...');
      try {
        final coreLogs = await _v2rayPlugin.getLogs();
        if (coreLogs != null && coreLogs.isNotEmpty) {
          _logger.info('V2Ray Core Logs (last ${coreLogs.length} entries):');
          // Log last 10 entries or all if less
          final logsToShow = coreLogs.length > 10 ? coreLogs.sublist(coreLogs.length - 10) : coreLogs;
          for (final log in logsToShow) {
            _logger.info('  [V2Ray Core] $log');
          }
        } else {
          _logger.warning('No V2Ray core logs available');
        }
      } catch (e) {
        _logger.warning('Failed to fetch V2Ray core logs: $e');
      }

      // Diagnostic 2: Verify core is responsive
      _logger.info('Diagnostic 2/3: Checking if V2Ray core is responsive...');
      try {
        final version = await _v2rayPlugin.getCoreVersion().timeout(const Duration(seconds: 3), onTimeout: () => '');
        if (version.isNotEmpty) {
          _logger.info('✓ V2Ray core is responsive - Version: $version');
        } else {
          _logger.warning('V2Ray core version check returned empty');
        }
      } catch (e) {
        _logger.error('V2Ray core responsiveness check failed: $e');
      }

      // Diagnostic 3: Log current connection state
      _logger.info('Diagnostic 3/3: Current connection state');
      _logger.info('  Status: $_status');
      _logger.info('  Server: ${_currentServer?.name}');
      _logger.info('  Address: ${_currentServer?.address}:${_currentServer?.port}');
      _logger.info('  Protocol: ${_currentServer?.protocol}');

      _logger.info('========== Diagnostics Complete ==========');
      _logger.info('');
      _logger.info('NEXT STEPS TO VERIFY CONNECTION:');
      _logger.info('1. Check the logs above for any [V2Ray Core] errors');
      _logger.info('2. Test actual traffic:');
      _logger.info('   - Open browser and visit https://ifconfig.me');
      _logger.info('   - Your IP should show VPN server location');
      _logger.info('3. If traffic still not routing, check:');
      _logger.info('   - Server configuration is correct');
      _logger.info('   - Server is actually reachable and working');
      _logger.info('   - No firewall blocking V2Ray');
    } catch (e, stackTrace) {
      _logger.error('Post-connection diagnostics failed: $e', stackTrace: stackTrace);
    }
  }

  // State management
  void _startLogPolling() {
    _logPollingTimer?.cancel();
    _logPollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_status != VPNConnectionStatus.connected) {
        timer.cancel();
        return;
      }

      try {
        final logs = await _v2rayPlugin.getLogs();
        if (logs.isNotEmpty) {
          for (var logMsg in logs) {
            // Only add if it looks like an actual V2Ray log and not one of our headers
            if (logMsg.contains('access:') || logMsg.contains('error:')) {
              _logger.info('[V2Ray Core] $logMsg');
            }
          }
        }
      } catch (e) {
        // Silent error for polling
      }
    });
  }

  void _stopLogPolling() {
    _logPollingTimer?.cancel();
    _logPollingTimer = null;
  }

  // Dispose resources
  void dispose() {
    _stopLogPolling();
    _statusController.close();
  }
}
