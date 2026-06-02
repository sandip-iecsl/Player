import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central access point for compile-time and runtime configuration values.
/// All API keys are loaded from the `.env` file at startup.
class AppConfig {
  AppConfig._();

  /// YouTube Data API v3 key. Empty string if not set in .env.
  static String get youtubeApiKey =>
      dotenv.env['YOUTUBE_API_KEY'] ?? '';

  /// Last.FM API key (optional — for future expansion).
  static String get lastFmApiKey =>
      dotenv.env['LASTFM_API_KEY'] ?? '';
}
