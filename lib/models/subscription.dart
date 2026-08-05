import 'dart:convert';

class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime lastUpdated;
  final List<String> serverIds;

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    DateTime? lastUpdated,
    List<String>? serverIds,
  })  : lastUpdated = lastUpdated ?? DateTime.now(),
        serverIds = serverIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'lastUpdated': lastUpdated.toIso8601String(),
        'serverIds': serverIds,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        serverIds: List<String>.from(json['serverIds'] ?? []),
      );
}

class SubscriptionService {
  static List<String> parseSubscriptionContent(String content) {
    final links = <String>[];

    try {
      String decoded;
      try {
        decoded = utf8.decode(base64.decode(_fixBase64(content)));
      } catch (_) {
        decoded = content;
      }

      for (final line in decoded.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('vmess://') || trimmed.startsWith('vless://')) {
          links.add(trimmed);
        }
      }
    } catch (_) {}

    return links;
  }

  static String _fixBase64(String input) {
    var result = input.replaceAll(RegExp(r'\s+'), '');
    while (result.length % 4 != 0) {
      result += '=';
    }
    return result;
  }
}
