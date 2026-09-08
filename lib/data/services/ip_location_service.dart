import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class IpLocationService {
  static Future<Map<String, double>?> getIpLocation() async {
    try {
      final dio = Dio();
      // ip-api is free for non-commercial use, 45 requests per minute limit
      final response = await dio.get('http://ip-api.com/json/');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'success') {
          return {
            'latitude': data['lat'] as double,
            'longitude': data['lon'] as double,
          };
        }
      }
    } catch (e) {
      debugPrint('[IpLocation] Fallback failed: $e');
    }
    return null;
  }
}
