# Aura Player - Music Player App

A feature-rich music player app built with Flutter.

## Features

- 🎵 Local music playback
- 🔍 Online music search (JioSaavn + Last.fm)
- 🎨 Beautiful visualizations
- 📱 Mobile support
- 🎯 Smart recommendations
- 📈 Trending charts

## Setup

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run the App
```bash
flutter run
```

### 3. Optional: Last.fm API (Better Recommendations)
1. Get free API key: https://www.last.fm/api/account/create
2. Add to `lib/config/lastfm_config.dart`:
```dart
static const String apiKey = 'your_api_key_here';
```

## Configuration

- **Last.fm Config:** `lib/config/lastfm_config.dart`
- **Spotify Config:** `lib/config/spotify_config.dart` (optional)

## Music Search

The app uses a hybrid search system:
1. **JioSaavn** - Primary source (works out of the box)
2. **Last.fm** - Enhanced recommendations (requires API key)
3. **Spotify** - Optional enhancement (requires OAuth)

## Troubleshooting

### Search not working?
- Check internet connection
- Verify Last.fm API key (if configured)
- Check console logs for error messages

### Songs won't play?
- Try a different song
- Check audio permissions
- Restart the app

## License

MIT License
