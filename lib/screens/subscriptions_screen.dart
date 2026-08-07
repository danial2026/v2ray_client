import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/subscription.dart';
import '../models/v2ray_server.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late StorageService _storage;
  List<Subscription> _subscriptions = [];
  List<V2RayServer> _allServers = [];
  bool _isLoading = false;
  String? _error;
  final Set<String> _expandedSubs = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _storage = await StorageService.init();
    setState(() {
      _subscriptions = _storage.loadSubscriptions();
      _allServers = _storage.loadServers();
    });
  }

  Future<void> _addSubscription() async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Add Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'Subscription URL', hintText: 'https://...'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'url': urlController.text.trim(),
                });
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      final sub = Subscription(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result['name']!,
        url: result['url']!,
      );

      await _storage.addSubscription(sub);
      setState(() {
        _subscriptions = _storage.loadSubscriptions();
      });
    }
  }

  Future<void> _updateSubscription(Subscription sub) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse(sub.url)).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Server responded with ${response.statusCode}');
      }

      final links = SubscriptionService.parseSubscriptionContent(response.body);
      if (links.isEmpty) {
        throw Exception('No valid links found in subscription');
      }

      await _storage.removeServersBySubscriptionId(sub.id);

      final serverIds = <String>[];
      for (final link in links) {
        try {
          final server = V2RayServer.fromAnyLink(link);
          final tagged = V2RayServer(
            id: server.id,
            name: server.name,
            address: server.address,
            port: server.port,
            uuid: server.uuid,
            protocol: server.protocol,
            alterId: server.alterId,
            network: server.network,
            type: server.type,
            host: server.host,
            path: server.path,
            tls: server.tls,
            security: server.security,
            encryption: server.encryption,
            flow: server.flow,
            sni: server.sni,
            alpn: server.alpn,
            fingerprint: server.fingerprint,
            publicKey: server.publicKey,
            shortId: server.shortId,
            spiderX: server.spiderX,
            subscriptionId: sub.id,
          );
          await _storage.addServer(tagged);
          serverIds.add(tagged.id);
        } catch (_) {}
      }

      if (serverIds.isEmpty) {
        throw Exception('Could not parse any servers from subscription');
      }

      // Reload servers from storage to get actual saved IDs (duplicate fix may have changed them)
      final savedServers = _storage.loadServers();
      final actualServerIds = savedServers
          .where((s) => s.subscriptionId == sub.id || serverIds.contains(s.id))
          .map((s) => s.id)
          .toList();

      final updatedSub = Subscription(
        id: sub.id,
        name: sub.name,
        url: sub.url,
        lastUpdated: DateTime.now(),
        serverIds: actualServerIds,
        expiryDate: _parseHeaderDate(response),
        uploadBytes: _parseHeaderInt(response, 'upload'),
        downloadBytes: _parseHeaderInt(response, 'download'),
        totalBytes: _parseHeaderInt(response, 'total'),
      );

      await _storage.updateSubscription(updatedSub);
      setState(() {
        _subscriptions = _storage.loadSubscriptions();
        _allServers = _storage.loadServers();
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${serverIds.length} server(s)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _deleteSubscription(String id) async {
    final currentSubs = _storage.loadSubscriptions();
    final sub = currentSubs.firstWhere((s) => s.id == id);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Remove Subscription'),
        content: Text('Remove "${sub.name}" and all its imported servers?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.removeServersBySubscriptionId(id);
      await _storage.removeSubscription(id);
      setState(() {
        _subscriptions = _storage.loadSubscriptions();
        _allServers = _storage.loadServers();
      });
    }
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  DateTime? _parseHeaderDate(http.Response response) {
    final info = SubscriptionService.parseUserInfoHeader(response.headers['subscription-userinfo']);
    final expire = info['expire'];
    if (expire != null) {
      return DateTime.fromMillisecondsSinceEpoch(expire * 1000);
    }
    return null;
  }

  int? _parseHeaderInt(http.Response response, String key) {
    final info = SubscriptionService.parseUserInfoHeader(response.headers['subscription-userinfo']);
    return info[key];
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildSubInfoRow(Subscription sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sub.remainingDays != null) ...[
          _buildRemainingDays(sub.remainingDays!),
          if (sub.usedBytes != null || sub.totalBytes != null) const SizedBox(height: 6),
        ],
        if (sub.usedBytes != null || sub.totalBytes != null)
          _buildTrafficBar(sub),
      ],
    );
  }

  Widget _buildRemainingDays(int days) {
    final color = days <= 3
        ? AppTheme.errorColor
        : days <= 7
            ? const Color(0xFFFFB74D)
            : const Color(0xFF66BB6A);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.access_time, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          days > 0 ? '$days day${days > 1 ? 's' : ''} left' : 'Expired',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }

  Widget _buildTrafficBar(Subscription sub) {
    final used = sub.usedBytes;
    final total = sub.totalBytes;
    final pct = sub.usedPercent;
    final progressColor = pct != null && pct > 0.9
        ? AppTheme.errorColor
        : pct != null && pct > 0.7
            ? const Color(0xFFFFB74D)
            : const Color(0xFF66BB6A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pct != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              width: 160,
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
          ),
          const SizedBox(height: 3),
        ],
        Row(
          children: [
            Icon(Icons.data_usage, size: 10, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Text(
              used != null ? _formatBytes(used) : '0 B',
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4)),
            ),
            if (total != null) ...[
              Text(
                ' / ${_formatBytes(total)}',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.25)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildServerListSublist(List<V2RayServer> servers) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in servers.take(25))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 5, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                  Text(
                    '${s.protocol.toUpperCase()} : ${s.port}',
                    style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3), fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          if (servers.length > 25)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${servers.length - 25} more...',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SUBSCRIPTIONS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: _addSubscription,
            tooltip: 'Add Subscription',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subscriptions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.subscriptions_outlined, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'No subscriptions',
                        style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      const SizedBox(height: 24),
                      TextButton(onPressed: _addSubscription, child: const Text('ADD SUBSCRIPTION')),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _subscriptions.length,
                  itemBuilder: (context, index) {
                    final sub = _subscriptions[index];
                    final isExpanded = _expandedSubs.contains(sub.id);
                    final subServers = _allServers.where((s) => s.subscriptionId == sub.id).toList();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: InkWell(
                        onTap: () => setState(() {
                          if (isExpanded) { _expandedSubs.remove(sub.id); } else { _expandedSubs.add(sub.id); }
                        }),
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: sub.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copied: ${sub.url}'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1)),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(isExpanded ? Icons.folder_open : Icons.subscriptions_outlined, size: 20, color: Colors.white.withValues(alpha: 0.5)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              '${sub.serverIds.length} servers',
                                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _timeAgo(sub.lastUpdated),
                                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.refresh, size: 18),
                                        onPressed: () => _updateSubscription(sub),
                                        color: Colors.white.withValues(alpha: 0.5),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () => _deleteSubscription(sub.id),
                                        color: Colors.white.withValues(alpha: 0.3),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (sub.remainingDays != null || sub.usedBytes != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10, left: 32),
                                  child: _buildSubInfoRow(sub),
                                ),
                              if (isExpanded && subServers.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8, left: 32),
                                  child: _buildServerListSublist(subServers),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _error != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppTheme.errorColor, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
