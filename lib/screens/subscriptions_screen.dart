import 'dart:async';
import 'package:flutter/material.dart';
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
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _storage = await StorageService.init();
    setState(() {
      _subscriptions = _storage.loadSubscriptions();
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

      final updatedSub = Subscription(
        id: sub.id,
        name: sub.name,
        url: sub.url,
        lastUpdated: DateTime.now(),
        serverIds: serverIds,
      );

      await _storage.updateSubscription(updatedSub);
      setState(() {
        _subscriptions = _storage.loadSubscriptions();
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
        content: Text('This will delete the subscription and all its imported servers.'),
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
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Icon(Icons.subscriptions_outlined, color: Colors.white.withValues(alpha: 0.5)),
                        title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Row(
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 18),
                              onPressed: () => _updateSubscription(sub),
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _deleteSubscription(sub.id),
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ],
                        ),
                        onTap: () => _updateSubscription(sub),
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
