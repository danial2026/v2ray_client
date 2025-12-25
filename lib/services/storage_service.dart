import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_server.dart';
import '../models/ping_settings.dart';
import '../models/ping_result.dart';
import '../models/dns_preset.dart';

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
    return jsonList.map((json) => V2RayServer.fromJson(json)).toList();
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

  // Clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
