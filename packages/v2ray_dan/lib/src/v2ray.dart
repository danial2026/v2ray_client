import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

class V2ray {
  static const MethodChannel _channel = MethodChannel('v2ray_dan');
  static const EventChannel _eventChannel = EventChannel('v2ray_dan/status');

  final Function(V2RayStatus status) onStatusChanged;

  V2ray({required this.onStatusChanged}) {
    _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is String) {
        onStatusChanged(V2RayStatus(state: event));
      }
    }, onError: (dynamic error) {
      // Handle error
    });
  }

  Future<String?> initialize({
    required String notificationIconResourceType,
    required String notificationIconResourceName,
  }) async {
    final String? filesDir = await _channel.invokeMethod('initialize', {
      'iconType': notificationIconResourceType,
      'iconName': notificationIconResourceName,
    });
    return filesDir;
  }

  Future<bool> requestPermission() async {
    try {
      final bool? result = await _channel.invokeMethod('requestPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> startV2Ray({
    required String remark,
    required String config,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    required bool proxyOnly,
    bool useSystemDns = true,
  }) async {
    await _channel.invokeMethod('startV2Ray', {
      'remark': remark,
      'config': config,
      'blockedApps': blockedApps,
      'bypassSubnets': bypassSubnets,
      'proxyOnly': proxyOnly,
      'useSystemDns': useSystemDns,
    });
  }

  Future<void> stopV2Ray() async {
    await _channel.invokeMethod('stopV2Ray');
  }

  Future<String> getCoreVersion() async {
    final String? version = await _channel.invokeMethod('getCoreVersion');
    return version ?? '';
  }

  Future<List<String>> getLogs() async {
    final List<dynamic>? logs = await _channel.invokeMethod('getLogs');
    return logs?.cast<String>() ?? [];
  }

  Future<int> getServerDelay({required String config, required String url}) async {
    final int? delay = await _channel.invokeMethod('getServerDelay', {
      'config': config,
      'url': url,
    });
    return delay ?? -1;
  }

  Future<List<String>> getSystemDns() async {
    final List<dynamic>? dns = await _channel.invokeMethod('getSystemDns');
    return dns?.cast<String>() ?? [];
  }

  Future<bool> setSystemProxy() async {
    try {
      final bool? result = await _channel.invokeMethod('setSystemProxy');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> clearSystemProxy() async {
    try {
      final bool? result = await _channel.invokeMethod('clearSystemProxy');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static V2RayURL parseFromURL(String url) {
    return V2RayURL(url);
  }
}

class V2RayStatus {
  final String state;
  V2RayStatus({required this.state});
}

class V2RayURL {
  final String url;
  String remark = "Default";

  V2RayURL(this.url) {
    if (url.startsWith("vmess://")) {
      try {
        String b64 = url.substring(8);
        while (b64.length % 4 != 0) b64 += "=";
        String decoded = utf8.decode(base64Decode(b64));
        Map<String, dynamic> jsonMap = jsonDecode(decoded);
        remark = jsonMap['ps'] ?? "V2Ray Server";
      } catch (e) {
        remark = "V2Ray Server";
      }
    } else if (url.startsWith("vless://")) {
      try {
        Uri uri = Uri.parse(url);
        remark = Uri.decodeComponent(uri.fragment);
        if (remark.isEmpty) remark = "V2Ray Server";
      } catch (e) {
        remark = "V2Ray Server";
      }
    }
  }

  String getFullConfiguration() {
    // Config generation is handled by the caller or native side in this custom impl
    return "{}";
  }
}
