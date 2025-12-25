import 'dart:async';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/v2ray_service.dart';
import 'services/logger_service.dart';

// Global V2Ray service instance for cleanup on crash
late V2RayService _globalV2RayService;
late LoggerService _logger;

void main() {
  // Catch async errors - logic must be inside the zone to match binding initialization
  runZonedGuarded(
    () {
      // Ensure Flutter binding is initialized inside the zone
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize services
      _globalV2RayService = V2RayService();
      _logger = LoggerService();

      // Setup error handling to disconnect VPN on crashes
      FlutterError.onError = (FlutterErrorDetails details) {
        _logger.error('Flutter Error: ${details.exception}', stackTrace: details.stack);
        _disconnectOnCrash();
        FlutterError.presentError(details);
      };

      runApp(const V2RayApp());
    },
    (error, stackTrace) {
      // We might need to initialize logger here if it wasn't initialized yet,
      // but since we moved it inside, we should be careful.
      // Ideally logging service uses a static instance or simplistic print if not ready.
      // But _logger is late, so we check if initialized or use print fallback.
      try {
        _logger.error('Uncaught error: $error', stackTrace: stackTrace);
      } catch (e) {
        debugPrint('Uncaught error (Logger not ready): $error');
      }
      _disconnectOnCrash();
    },
  );
}

// Emergency VPN disconnect on crash
void _disconnectOnCrash() {
  try {
    _logger.warning('!!! CRASH DETECTED - Disconnecting VPN for safety !!!');
    // Use unawaited to not block crash handling
    _globalV2RayService.disconnect().whenComplete(() {
      _logger.info('VPN disconnected after crash');
    });
  } catch (e) {
    _logger.error('Failed to disconnect VPN on crash: $e');
  }
}

class V2RayApp extends StatefulWidget {
  const V2RayApp({super.key});

  @override
  State<V2RayApp> createState() => _V2RayAppState();
}

class _V2RayAppState extends State<V2RayApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Disconnect VPN when app is destroyed
    _logger.info('App disposing - disconnecting VPN');
    _globalV2RayService.disconnect();
    _globalV2RayService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _logger.info('App lifecycle state changed: $state');

    // Optional: Disconnect when app is detached (being closed by system)
    if (state == AppLifecycleState.detached) {
      _logger.info('App detached - disconnecting VPN');
      _globalV2RayService.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Flaming Cherubim', theme: AppTheme.darkTheme, debugShowCheckedModeBanner: false, home: const HomeScreen());
  }
}
