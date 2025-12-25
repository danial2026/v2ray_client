enum ProxyMode {
  http,
  socks,
  both;

  String get displayName {
    switch (this) {
      case ProxyMode.http:
        return 'HTTP';
      case ProxyMode.socks:
        return 'SOCKS';
      case ProxyMode.both:
        return 'BOTH';
    }
  }

  String toJson() => name;

  static ProxyMode fromJson(String json) {
    try {
      return ProxyMode.values.firstWhere((e) => e.name == json);
    } catch (_) {
      return ProxyMode.socks; // Default fallback
    }
  }

  static ProxyMode get defaultMode => ProxyMode.socks;
}
