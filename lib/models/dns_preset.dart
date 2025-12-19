class DnsPreset {
  final String id;
  final String name;
  final String address;

  DnsPreset({required this.id, required this.name, required this.address});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'address': address};

  factory DnsPreset.fromJson(Map<String, dynamic> json) =>
      DnsPreset(id: json['id'] as String, name: json['name'] as String, address: json['address'] as String);
}
