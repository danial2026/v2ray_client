import 'dart:convert';
import 'package:http/http.dart' as http;

class IpInfoService {
  static const String _apiUrl = 'http://ip-api.com/json/';

  Future<IpInfo?> fetchIpInfo() async {
    try {
      final response = await http.get(Uri.parse(_apiUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return IpInfo(
          ip: data['query'] ?? 'Unknown',
          countryCode: data['countryCode'] ?? 'XX',
          country: data['country'] ?? 'Unknown',
        );
      }
    } catch (e) {
      // Failed to fetch IP info
    }
    return null;
  }
}

class IpInfo {
  final String ip;
  final String countryCode;
  final String country;

  IpInfo({
    required this.ip,
    required this.countryCode,
    required this.country,
  });

  String get flagEmoji {
    if (countryCode == 'XX') return '🌐';
    return countryCode.toUpperCase().replaceAllMapped(RegExp(r'[A-Z]'), (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) + 127397));
  }
}
