import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_server.dart';
import '../models/ping_settings.dart';
import '../models/ping_result.dart';
import '../models/dns_preset.dart';
import '../models/proxy_mode.dart';
import '../models/subscription.dart';

class StorageService {
  static const String _serversKey = 'v2ray_servers';
  static const String _pingSettingsKey = 'ping_settings';
  static const String _pingResultsKey = 'ping_results';
  static const String _customDnsKey = 'custom_dns';
  static const String _selectedServerKey = 'selected_server_id';
  static const String _proxyOnlyKey = 'proxy_only';
  static const String _useSystemDnsKey = 'use_system_dns';
  static const String _dnsPresetsKey = 'dns_presets';
  static const String _autoPingEnabledKey = 'auto_ping_enabled';
  static const String _showUsageStatsKey = 'show_usage_stats';
  static const String _censorAddressesKey = 'censor_addresses';
  static const String _urlHistoryKey = 'url_history';
  static const String _proxyModeKey = 'proxy_mode';
  static const String _socksPortKey = 'socks_port';
  static const String _httpPortKey = 'http_port';
  static const String _subscriptionsKey = 'subscriptions';
  static const String _setSystemProxyKey = 'set_system_proxy';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // Initialize storage service
  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // Custom DNS operations
  Future<void> saveCustomDns(String? dns) async {
    if (dns == null) {
      await _prefs.remove(_customDnsKey);
    } else {
      await _prefs.setString(_customDnsKey, dns);
    }
  }

  String? loadCustomDns() {
    return _prefs.getString(_customDnsKey);
  }

  // Server operations
  Future<void> saveServers(List<V2RayServer> servers) async {
    final jsonList = servers.map((s) => s.toJson()).toList();
    await _prefs.setString(_serversKey, json.encode(jsonList));
  }

  List<V2RayServer> loadServers() {
    final jsonString = _prefs.getString(_serversKey);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = json.decode(jsonString);
    final servers = jsonList.map((json) => V2RayServer.fromJson(json)).toList();

    final (fixed, remap) = _fixDuplicateServerIds(servers);
    if (fixed != null) {
      _updateSubscriptionRefs(remap);
      final fixedJson = fixed.map((s) => s.toJson()).toList();
      _prefs.setString(_serversKey, json.encode(fixedJson));
      return fixed;
    }
    return servers;
  }

  (List<V2RayServer>?, Map<String, List<String>>) _fixDuplicateServerIds(List<V2RayServer> servers) {
    final seen = <String>{};
    var hasDupes = false;
    for (final s in servers) {
      if (seen.contains(s.id)) { hasDupes = true; break; }
      seen.add(s.id);
    }
    if (!hasDupes) return (null, {});

    final counter = DateTime.now().millisecondsSinceEpoch;
    final remap = <String, List<String>>{};
    final used = <String>{};
    final fixed = <V2RayServer>[];

    for (var i = 0; i < servers.length; i++) {
      final s = servers[i];
      if (used.contains(s.id)) {
        final newId = '${s.id}_$counter$i';
        remap.putIfAbsent(s.id, () => []).add(newId);
        fixed.add(V2RayServer(id: newId, name: s.name, address: s.address, port: s.port, uuid: s.uuid, protocol: s.protocol, alterId: s.alterId, network: s.network, type: s.type, host: s.host, path: s.path, tls: s.tls, security: s.security, encryption: s.encryption, flow: s.flow, sni: s.sni, alpn: s.alpn, fingerprint: s.fingerprint, publicKey: s.publicKey, shortId: s.shortId, spiderX: s.spiderX, subscriptionId: s.subscriptionId, createdAt: s.createdAt));
      } else {
        used.add(s.id);
        fixed.add(s);
      }
    }
    return (fixed, remap);
  }

  void _updateSubscriptionRefs(Map<String, List<String>> remap) {
    if (remap.isEmpty) return;
    final subs = loadSubscriptions();
    for (final sub in subs) {
      final newIds = <String>[];
      for (final id in sub.serverIds) {
        if (remap.containsKey(id)) {
          newIds.add(id); // keep the original (first occurrence)
          newIds.addAll(remap[id]!); // add all remapped duplicates
        } else {
          newIds.add(id);
        }
      }
      sub.serverIds
        ..clear()
        ..addAll(newIds);
    }
    saveSubscriptions(subs);
  }

  Future<void> addServer(V2RayServer server) async {
    final servers = loadServers();
    servers.add(server);
    await saveServers(servers);
  }

  Future<void> updateServer(V2RayServer server) async {
    final servers = loadServers();
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      servers[index] = server;
      await saveServers(servers);
    }
  }

  Future<void> removeServer(String serverId) async {
    final servers = loadServers();
    servers.removeWhere((s) => s.id == serverId);
    await saveServers(servers);
  }

  Future<void> removeServers(List<String> serverIds) async {
    final servers = loadServers();
    servers.removeWhere((s) => serverIds.contains(s.id));
    await saveServers(servers);
  }

  Future<void> removeServersBySubscriptionId(String subId) async {
    final servers = loadServers();
    servers.removeWhere((s) => s.subscriptionId == subId);
    await saveServers(servers);
  }

  // Ping settings operations
  Future<void> savePingSettings(PingSettings settings) async {
    await _prefs.setString(_pingSettingsKey, json.encode(settings.toJson()));
  }

  PingSettings loadPingSettings() {
    final jsonString = _prefs.getString(_pingSettingsKey);
    if (jsonString == null) return PingSettings.defaultSettings;

    return PingSettings.fromJson(json.decode(jsonString));
  }

  // Ping results operations
  Future<void> savePingResults(Map<String, PingResult> results) async {
    final jsonMap = results.map((key, value) => MapEntry(key, value.toJson()));
    await _prefs.setString(_pingResultsKey, json.encode(jsonMap));
  }

  Map<String, PingResult> loadPingResults() {
    final jsonString = _prefs.getString(_pingResultsKey);
    if (jsonString == null) return {};

    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    return jsonMap.map((key, value) => MapEntry(key, PingResult.fromJson(value)));
  }

  // Selected server operations
  Future<void> saveSelectedServerId(String? serverId) async {
    if (serverId == null) {
      await _prefs.remove(_selectedServerKey);
    } else {
      await _prefs.setString(_selectedServerKey, serverId);
    }
  }

  String? loadSelectedServerId() {
    return _prefs.getString(_selectedServerKey);
  }

  // Proxy Only operations
  Future<void> saveProxyOnly(bool proxyOnly) async {
    await _prefs.setBool(_proxyOnlyKey, proxyOnly);
  }

  bool loadProxyOnly() {
    return _prefs.getBool(_proxyOnlyKey) ?? false;
  }

  // System DNS operations
  Future<void> saveUseSystemDns(bool useSystemDns) async {
    await _prefs.setBool(_useSystemDnsKey, useSystemDns);
  }

  bool loadUseSystemDns() {
    return _prefs.getBool(_useSystemDnsKey) ?? true;
  }

  // DNS Presets operations
  Future<void> saveDnsPresets(List<DnsPreset> presets) async {
    final jsonList = presets.map((p) => p.toJson()).toList();
    await _prefs.setString(_dnsPresetsKey, json.encode(jsonList));
  }

  List<DnsPreset> loadDnsPresets() {
    final jsonString = _prefs.getString(_dnsPresetsKey);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((j) => DnsPreset.fromJson(j)).toList();
  }

  // Auto-ping settings
  Future<void> saveAutoPingEnabled(bool enabled) async {
    await _prefs.setBool(_autoPingEnabledKey, enabled);
  }

  bool loadAutoPingEnabled() {
    return _prefs.getBool(_autoPingEnabledKey) ?? false;
  }

  // Usage Stats settings
  Future<void> saveShowUsageStats(bool show) async {
    await _prefs.setBool(_showUsageStatsKey, show);
  }

  bool loadShowUsageStats() {
    return _prefs.getBool(_showUsageStatsKey) ?? false;
  }

  // Censoring settings
  Future<void> saveCensorAddresses(bool censor) async {
    await _prefs.setBool(_censorAddressesKey, censor);
  }

  bool loadCensorAddresses() {
    return _prefs.getBool(_censorAddressesKey) ?? false;
  }

  // URL History
  Future<void> saveUrlHistory(List<String> history) async {
    await _prefs.setStringList(_urlHistoryKey, history);
  }

  List<String> loadUrlHistory() {
    return _prefs.getStringList(_urlHistoryKey) ?? [];
  }

  // Proxy Mode operations (macOS)
  Future<void> saveProxyMode(ProxyMode mode) async {
    await _prefs.setString(_proxyModeKey, mode.toJson());
  }

  ProxyMode loadProxyMode() {
    final modeStr = _prefs.getString(_proxyModeKey);
    if (modeStr == null) return ProxyMode.defaultMode;
    return ProxyMode.fromJson(modeStr);
  }

  // Custom port operations
  Future<void> saveSocksPort(int port) async {
    await _prefs.setInt(_socksPortKey, port);
  }

  int loadSocksPort() {
    return _prefs.getInt(_socksPortKey) ?? 10808;
  }

  Future<void> saveHttpPort(int port) async {
    await _prefs.setInt(_httpPortKey, port);
  }

  int loadHttpPort() {
    return _prefs.getInt(_httpPortKey) ?? 10809;
  }

  // Subscription operations
  Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    final jsonList = subscriptions.map((s) => s.toJson()).toList();
    await _prefs.setString(_subscriptionsKey, json.encode(jsonList));
  }

  List<Subscription> loadSubscriptions() {
    final jsonString = _prefs.getString(_subscriptionsKey);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((j) => Subscription.fromJson(j)).toList();
  }

  Future<void> addSubscription(Subscription subscription) async {
    final subs = loadSubscriptions();
    subs.add(subscription);
    await saveSubscriptions(subs);
  }

  Future<void> updateSubscription(Subscription subscription) async {
    final subs = loadSubscriptions();
    final index = subs.indexWhere((s) => s.id == subscription.id);
    if (index != -1) {
      subs[index] = subscription;
      await saveSubscriptions(subs);
    }
  }

  Future<void> removeSubscription(String id) async {
    final subs = loadSubscriptions();
    subs.removeWhere((s) => s.id == id);
    await saveSubscriptions(subs);
  }

  // Duplicate detection
  List<List<V2RayServer>> findDuplicates() {
    final servers = loadServers();
    final seen = <String, List<V2RayServer>>{};

    for (final server in servers) {
      final key = '${server.address}:${server.port}:${server.uuid}';
      seen.putIfAbsent(key, () => []);
      seen[key]!.add(server);
    }

    return seen.values.where((list) => list.length > 1).toList();
  }

  Future<void> removeDuplicateServers() async {
    final duplicates = findDuplicates();
    if (duplicates.isEmpty) return;

    final servers = loadServers();
    final toRemoveIds = <String>{};

    for (final group in duplicates) {
      for (int i = 1; i < group.length; i++) {
        toRemoveIds.add(group[i].id);
      }
    }

    servers.removeWhere((s) => toRemoveIds.contains(s.id));
    await saveServers(servers);
  }

  // System proxy toggle
  Future<void> saveSetSystemProxy(bool value) async {
    await _prefs.setBool(_setSystemProxyKey, value);
  }

  bool loadSetSystemProxy() {
    return _prefs.getBool(_setSystemProxyKey) ?? true;
  }

  // Clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
