import 'dart:convert';

class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime lastUpdated;
  final List<String> serverIds;

  // Optional info from subscription-userinfo header
  final DateTime? expiryDate;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    DateTime? lastUpdated,
    List<String>? serverIds,
    this.expiryDate,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
  })  : lastUpdated = lastUpdated ?? DateTime.now(),
        serverIds = serverIds ?? [];

  int? get remainingDays {
    if (expiryDate == null) return null;
    final diff = expiryDate!.difference(DateTime.now());
    return diff.inDays;
  }

  int? get usedBytes {
    if (uploadBytes == null && downloadBytes == null) return null;
    return (uploadBytes ?? 0) + (downloadBytes ?? 0);
  }

  double? get usedPercent {
    if (totalBytes == null || totalBytes == 0) return null;
    final u = usedBytes;
    if (u == null) return null;
    return (u / totalBytes!).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'lastUpdated': lastUpdated.toIso8601String(),
        'serverIds': serverIds,
        if (expiryDate != null) 'expiryDate': expiryDate!.millisecondsSinceEpoch,
        if (uploadBytes != null) 'uploadBytes': uploadBytes,
        if (downloadBytes != null) 'downloadBytes': downloadBytes,
        if (totalBytes != null) 'totalBytes': totalBytes,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        serverIds: List<String>.from(json['serverIds'] ?? []),
        expiryDate: json['expiryDate'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['expiryDate'] as int)
            : null,
        uploadBytes: json['uploadBytes'] as int?,
        downloadBytes: json['downloadBytes'] as int?,
        totalBytes: json['totalBytes'] as int?,
      );
}

class SubscriptionService {
  static Map<String, int?> parseUserInfoHeader(String? headerValue) {
    final result = <String, int?>{'upload': null, 'download': null, 'total': null, 'expire': null};
    if (headerValue == null || headerValue.isEmpty) return result;

    for (final part in headerValue.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length != 2) continue;
      final key = kv[0].trim();
      final val = int.tryParse(kv[1].trim());
      if (key == 'upload') result['upload'] = val;
      if (key == 'download') result['download'] = val;
      if (key == 'total') result['total'] = val;
      if (key == 'expire') result['expire'] = val;
    }
    return result;
  }

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
