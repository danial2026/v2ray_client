import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ping_settings.dart';
import '../models/dns_preset.dart';
import '../services/storage_service.dart';
import '../services/v2ray_service.dart';
import '../theme/app_theme.dart';
import 'changelog_page.dart';

class PingSettingsScreen extends StatefulWidget {
  final PingSettings currentSettings;

  const PingSettingsScreen({super.key, required this.currentSettings});

  @override
  State<PingSettingsScreen> createState() => _PingSettingsScreenState();
}

class _PingSettingsScreenState extends State<PingSettingsScreen> {
  late int _chunkSize;
  late int _timeoutPerPing;
  late int _pingSize;
  late int _timeoutPerChunk;
  late int _retryCount;
  late bool _useCustomDns;
  late bool _autoPingEnabled;
  PackageInfo _packageInfo = PackageInfo(
    appName: 'Unknown',
    packageName: 'Unknown',
    version: 'Unknown',
    buildNumber: 'Unknown',
    buildSignature: 'Unknown',
    installerStore: 'Unknown',
  );
  final TextEditingController _dnsController = TextEditingController();

  List<DnsPreset> _dnsPresets = [];

  final List<DnsPreset> _defaultPresets = [
    DnsPreset(id: 'shecan', name: 'Shecan.ir', address: '178.22.122.100, 185.51.200.2'),
    DnsPreset(id: 'google', name: 'Google DNS', address: '8.8.8.8, 8.8.4.4'),
    DnsPreset(id: 'cloudflare', name: 'Cloudflare', address: '1.1.1.1, 1.0.0.1'),
    DnsPreset(id: 'adguard', name: 'AdGuard', address: '94.140.14.14, 94.140.15.15'),
    DnsPreset(id: 'quad9', name: 'Quad9', address: '9.9.9.9, 149.112.112.112'),
  ];

  @override
  void initState() {
    super.initState();
    _chunkSize = widget.currentSettings.chunkSize;
    _timeoutPerPing = widget.currentSettings.timeoutPerPing;
    _pingSize = widget.currentSettings.pingSize;
    _timeoutPerChunk = widget.currentSettings.timeoutPerChunk;
    _retryCount = widget.currentSettings.retryCount;
    _useCustomDns = false; // logic inverted: useCustomDns means !useSystemDns
    _autoPingEnabled = true;
    _initializeData();
  }

  Future<void> _initializeData() async {
    final storage = await StorageService.init();
    final systemDns = storage.loadUseSystemDns();
    final presets = storage.loadDnsPresets();

    setState(() {
      _dnsController.text = storage.loadCustomDns() ?? '';
      _useCustomDns = !systemDns;
      _autoPingEnabled = storage.loadAutoPingEnabled();
      _dnsPresets = presets.isEmpty ? _defaultPresets : presets;
    });

    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  void _saveSettings() async {
    final storage = await StorageService.init();
    await storage.saveCustomDns(_dnsController.text.trim());
    await storage.saveUseSystemDns(!_useCustomDns);
    await storage.saveAutoPingEnabled(_autoPingEnabled);
    await storage.saveDnsPresets(_dnsPresets);

    final settings = PingSettings(
      chunkSize: _chunkSize,
      timeoutPerPing: _timeoutPerPing,
      pingSize: _pingSize,
      timeoutPerChunk: _timeoutPerChunk,
      retryCount: _retryCount,
    );
    if (mounted) {
      Navigator.pop(context, settings);
    }
  }

  void _resetToDefaults() {
    setState(() {
      _chunkSize = PingSettings.defaultSettings.chunkSize;
      _timeoutPerPing = PingSettings.defaultSettings.timeoutPerPing;
      _pingSize = PingSettings.defaultSettings.pingSize;
      _timeoutPerChunk = PingSettings.defaultSettings.timeoutPerChunk;
      _retryCount = PingSettings.defaultSettings.retryCount;
    });
  }

  void _addDnsPreset() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Add DNS Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g. Shecan)'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address (e.g. 1.1.1.1)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && addressController.text.isNotEmpty) {
                setState(() {
                  _dnsPresets.add(
                    DnsPreset(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text.trim(),
                      address: addressController.text.trim(),
                    ),
                  );
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeDnsPreset(String id) {
    if (_dnsPresets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one DNS preset is required')));
      return;
    }
    setState(() {
      _dnsPresets.removeWhere((p) => p.id == id);
    });
  }

  void _selectDnsPreset(DnsPreset preset) {
    setState(() {
      _dnsController.text = preset.address;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PING ENGINE'),
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: Text(
              'RESET',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            _buildSectionHeader('BATCH PROCESSING'),
            const SizedBox(height: 24),

            // Chunk Size
            _buildSliderSetting(
              label: 'CONCURRENCY',
              description: 'Number of parallel ICMP requests',
              value: _chunkSize.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              displayValue: '$_chunkSize UNITS',
              onChanged: (value) => setState(() => _chunkSize = value.round()),
            ),

            const SizedBox(height: 40),
            _buildSectionHeader('PACKET TIMEOUTS'),
            const SizedBox(height: 24),

            // Timeout per Ping
            _buildSliderSetting(
              label: 'REQUEST TIMEOUT',
              description: 'Max wait time for individual reply',
              value: _timeoutPerPing.toDouble(),
              min: 1,
              max: 15,
              divisions: 14,
              displayValue: '${_timeoutPerPing}S',
              onChanged: (value) => setState(() => _timeoutPerPing = value.round()),
            ),

            const SizedBox(height: 32),

            // Timeout per Chunk
            _buildSliderSetting(
              label: 'BATCH TIMEOUT',
              description: 'Max time for a group of servers',
              value: _timeoutPerChunk.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              displayValue: '${_timeoutPerChunk}S',
              onChanged: (value) => setState(() => _timeoutPerChunk = value.round()),
            ),

            const SizedBox(height: 32),
            _buildCustomDnsToggle(),

            if (_useCustomDns) ...[const SizedBox(height: 24), _buildDnsPresetsList()],

            const SizedBox(height: 32),
            _buildSectionHeader('SYSTEM'),
            const SizedBox(height: 24),
            _buildAutoPingToggle(),

            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _saveSettings, child: const Text('APPLY SETTINGS')),
            ),

            const SizedBox(height: 48),
            _buildAboutSection(),

            const SizedBox(height: 64),
            _buildSystemResetSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 8),
        Container(width: 40, height: 1, color: Colors.white.withValues(alpha: 0.1)),
      ],
    );
  }

  Widget _buildSliderSetting({
    required String label,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1)),
                Text(description, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
              ],
            ),
            Text(
              displayValue,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.successColor),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.05),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.1),
          ),
          child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
        ),
      ],
    );
  }

  // Removed old _buildCustomDnsInput in favor of presets list for cleaner UI

  Widget _buildCustomDnsToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(_useCustomDns ? Icons.settings_ethernet : Icons.dns_outlined, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CUSTOM DNS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  Text('Manually define DNS providers', style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.3))),
                ],
              ),
            ],
          ),
          Switch(
            value: _useCustomDns,
            onChanged: (value) => setState(() => _useCustomDns = value),
            activeThumbColor: AppTheme.accentColor,
            activeTrackColor: AppTheme.accentColor.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoPingToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.speed_outlined, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AUTO PING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  Text('Ping servers on connect/disconnect', style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.3))),
                ],
              ),
            ],
          ),
          Switch(
            value: _autoPingEnabled,
            onChanged: (value) => setState(() => _autoPingEnabled = value),
            activeThumbColor: AppTheme.accentColor,
            activeTrackColor: AppTheme.accentColor.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildDnsPresetsList() {
    return Column(
      children: [
        ..._dnsPresets.map((preset) {
          final isSelected = _dnsController.text.trim() == preset.address;
          return _buildDnsPresetCard(preset, isSelected);
        }),
        const SizedBox(height: 8),
        _buildAddPresetButton(),
      ],
    );
  }

  Widget _buildDnsPresetCard(DnsPreset preset, bool isSelected) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05), width: 1),
      ),
      child: InkWell(
        onTap: () => _selectDnsPreset(preset),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Selection Indicator
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),

              // Preset Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.address,
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5), fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Remove Action
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _removeDnsPreset(preset.id),
                color: Colors.white.withValues(alpha: 0.2),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddPresetButton() {
    return InkWell(
      onTap: _addDnsPreset,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: Colors.white.withValues(alpha: 0.3), size: 18),
            const SizedBox(width: 12),
            Text(
              'ADD NEW PRESET',
              style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection() {
    return Column(
      children: [
        _buildSectionHeader('ABOUT'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback to icon if image not found
                        return const Icon(Icons.info_outline, color: AppTheme.accentColor, size: 36);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Flaming Cherubim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        GestureDetector(
                          onTap: () => _launchURL('https://www.danials.org/'),
                          child: Text(
                            'v${_packageInfo.version}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white10),
              const SizedBox(height: 16),
              _buildAboutItem(label: 'DEVELOPER', value: 'Danial', icon: Icons.person_outline),
              const SizedBox(height: 12),
              _buildAboutItem(
                label: 'VERSION',
                value: 'v${_packageInfo.version}',
                icon: Icons.info_outline,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangelogPage()));
                },
              ),
              const SizedBox(height: 12),
              _buildAboutItem(
                label: 'WEBSITE',
                value: 'https://danials.org',
                icon: Icons.language,
                isLink: true,
                onTap: () => _launchURL('https://www.danials.org/'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAboutItem({required String label, required String value, required IconData icon, bool isLink = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.3)),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: isLink ? 16 : 13,
                fontWeight: isLink ? FontWeight.w700 : FontWeight.w600,
                color: isLink ? Colors.white : Colors.white.withValues(alpha: 0.7),
                decoration: isLink ? TextDecoration.underline : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: try with platformDefault mode
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      // Show error to user if URL launch fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open URL: $e')));
      }
    }
  }

  Widget _buildSystemResetSection() {
    return Column(
      children: [
        _buildSectionHeader('DANGER ZONE'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              const Icon(Icons.restart_alt_rounded, size: 48, color: AppTheme.errorColor),
              const SizedBox(height: 16),
              const Text(
                'System Reset',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.errorColor),
              ),
              const SizedBox(height: 8),
              Text(
                'If the VPN is stuck or crashing, this will force stop all connections and relaunch the app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor.withValues(alpha: 0.1),
                    foregroundColor: AppTheme.errorColor,
                    shadowColor: Colors.transparent,
                    side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.5)),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppTheme.surfaceColor,
                        title: const Text('Confirm Reset', style: TextStyle(color: AppTheme.errorColor)),
                        content: const Text(
                          'This will forcefully terminate all VPN processes and close the application. You will need to manually open the app again.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
                            onPressed: () {
                              Navigator.pop(context);
                              V2RayService().fullSystemReset();
                            },
                            child: const Text('RESET & RELAUNCH'),
                          ),
                        ],
                      ),
                    );

                    // Actually implementing the reset action here:
                    // Since I can't easily add the import in this same step without using multi_replace (which I should use),
                    // I will define the action assuming the import exists.
                  },
                  child: const Text('RESET VPN & RELAUNCH APP'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _dnsController.dispose();
    super.dispose();
  }
}
