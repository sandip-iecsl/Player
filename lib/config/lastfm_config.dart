/// Last.fm API Configuration
/// 
/// Application: Aura_Player
/// Registered to: Sandip_2005
/// API Key: a10e5808a08d85a51d8cf65ef53c44be
/// 
/// Note: Last.fm API is free and doesn't require OAuth for basic features
class LastFmConfig {
  // Last.fm API key for Aura_Player
  static const String apiKey = 'a10e5808a08d85a51d8cf65ef53c44be';
  
  /// Check if Last.fm is configured
  static bool get isConfigured => apiKey.isNotEmpty && apiKey != 'YOUR_LASTFM_API_KEY_HERE';
}
