import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // YouTube API Configuration
  static String get youtubeApiKey {
    final key = dotenv.env['YOUTUBE_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception(
        'YOUTUBE_API_KEY not found in .env file. '
        'Please copy .env.example to .env and add your API key.'
      );
    }
    return key;
  }
  
  // Deezer API Configuration
  // No API key required - Deezer allows free public access
  static const String deezerBaseUrl = 'https://api.deezer.com';
  
  // API Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
  
  // Cache Configuration
  static const Duration cacheDuration = Duration(hours: 1);
  
  // Pagination
  static const int defaultPageSize = 20;
}
