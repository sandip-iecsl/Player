import 'package:flutter/foundation.dart';
import '../../../../data/models/song_model.dart';
import '../../../../domain/entities/song.dart';

/// Supported Search Providers in Aura Player
enum SearchProviderType {
  local('Local Cache & Storage'),
  audius('Audius Music'),
  jamendo('Jamendo Open Music'),
  jiosaavn('JioSaavn Stream'),
  deezer('Deezer Preview/Meta'),
  youtube('YouTube Data API & Proxy'),
  spotify('Spotify Web API Meta'),
  mongodb('MongoDB Atlas Indexed');

  final String displayName;
  const SearchProviderType(this.displayName);
}

/// Version classification of audio tracks
enum TrackVersionType {
  official,
  officialAudio,
  musicVideo,
  live,
  acoustic,
  remix,
  slowed,
  lofi,
  cover,
  lyrics,
  karaoke,
  reaction,
  compilation,
  short,
  podcast,
  unknown;

  static TrackVersionType fromString(String? val) {
    if (val == null || val.isEmpty) return TrackVersionType.unknown;
    final lower = val.toLowerCase().trim();
    for (final type in TrackVersionType.values) {
      if (type.name.toLowerCase() == lower) return type;
    }
    return TrackVersionType.unknown;
  }
}

/// Detected Query Intent
enum QueryIntent {
  song,
  artist,
  album,
  playlist,
  lyrics,
  live,
  remix,
  slowed,
  lofi,
  cover,
  acoustic,
  karaoke,
  discovery,
  unknown;

  static QueryIntent fromString(String? val) {
    if (val == null || val.isEmpty) return QueryIntent.unknown;
    final lower = val.toLowerCase().trim();
    for (final intent in QueryIntent.values) {
      if (intent.name.toLowerCase() == lower) return intent;
    }
    return QueryIntent.unknown;
  }
}

/// Extracted semantic entities from a search query
@immutable
class QueryEntities {
  final String? artist;
  final String? title;
  final String? album;
  final int? year;
  final String? language;
  final TrackVersionType? version;
  final List<String> modifiers;

  const QueryEntities({
    this.artist,
    this.title,
    this.album,
    this.year,
    this.language,
    this.version,
    this.modifiers = const [],
  });

  Map<String, dynamic> toJson() => {
    'artist': artist,
    'title': title,
    'album': album,
    'year': year,
    'language': language,
    'version': version?.name,
    'modifiers': modifiers,
  };

  factory QueryEntities.fromJson(Map<String, dynamic> json) {
    return QueryEntities(
      artist: json['artist'] as String?,
      title: json['title'] as String?,
      album: json['album'] as String?,
      year: json['year'] as int?,
      language: json['language'] as String?,
      version: json['version'] != null ? TrackVersionType.fromString(json['version'] as String) : null,
      modifiers: (json['modifiers'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

/// Parsed & Normalized Query representation produced by Query Intelligence
@immutable
class ParsedQuery {
  final String raw;
  final String normalized;
  final String corrected;
  final QueryIntent intent;
  final QueryEntities entities;
  final String? detectedLanguage;
  final List<String> transliteratedVariants;
  final List<String> synonyms;
  final List<String> tokens;

  const ParsedQuery({
    required this.raw,
    required this.normalized,
    required this.corrected,
    required this.intent,
    required this.entities,
    this.detectedLanguage,
    this.transliteratedVariants = const [],
    this.synonyms = const [],
    this.tokens = const [],
  });

  String get effectiveQuery => corrected.isNotEmpty ? corrected : normalized;

  Map<String, dynamic> toJson() => {
    'raw': raw,
    'normalized': normalized,
    'corrected': corrected,
    'intent': intent.name,
    'entities': entities.toJson(),
    'detectedLanguage': detectedLanguage,
    'transliteratedVariants': transliteratedVariants,
    'synonyms': synonyms,
    'tokens': tokens,
  };
}

/// Canonical Music Search Candidate unified across all providers
@immutable
class SearchCandidate {
  final String canonicalId;
  final String? youtubeId;
  final String? audiusId;
  final String? jamendoId;
  final String? jioSaavnId;
  final String? spotifyId;
  final String? deezerId;
  final String? isrc;
  final String? musicBrainzId;

  final String title;
  final String artist;
  final String? album;
  final String? channelOrOwner;

  final String normalizedTitle;
  final String normalizedArtist;
  final String? normalizedAlbum;

  final Duration duration;
  final String? language;
  final String? region;
  final TrackVersionType versionType;
  final SearchProviderType sourceProvider;

  final int? viewCount;
  final int? likeCount;
  final double? popularityScore; // 0.0 to 1.0
  final DateTime? publishedAt;

  final String? artworkUrl;
  final String? playableUrl;
  final String? previewUrl;
  final bool isDownloadable;
  final String? audioFormat;
  final String? bitrate;

  final Map<String, dynamic> providerMetadata;
  final List<SearchProviderType> matchedProviders;

  const SearchCandidate({
    required this.canonicalId,
    this.youtubeId,
    this.audiusId,
    this.jamendoId,
    this.jioSaavnId,
    this.spotifyId,
    this.deezerId,
    this.isrc,
    this.musicBrainzId,
    required this.title,
    required this.artist,
    this.album,
    this.channelOrOwner,
    required this.normalizedTitle,
    required this.normalizedArtist,
    this.normalizedAlbum,
    required this.duration,
    this.language,
    this.region,
    this.versionType = TrackVersionType.official,
    required this.sourceProvider,
    this.viewCount,
    this.likeCount,
    this.popularityScore,
    this.publishedAt,
    this.artworkUrl,
    this.playableUrl,
    this.previewUrl,
    this.isDownloadable = false,
    this.audioFormat,
    this.bitrate,
    this.providerMetadata = const {},
    this.matchedProviders = const [],
  });

  SearchCandidate copyWith({
    String? canonicalId,
    String? youtubeId,
    String? audiusId,
    String? jamendoId,
    String? jioSaavnId,
    String? spotifyId,
    String? deezerId,
    String? isrc,
    String? musicBrainzId,
    String? title,
    String? artist,
    String? album,
    String? channelOrOwner,
    String? normalizedTitle,
    String? normalizedArtist,
    String? normalizedAlbum,
    Duration? duration,
    String? language,
    String? region,
    TrackVersionType? versionType,
    SearchProviderType? sourceProvider,
    int? viewCount,
    int? likeCount,
    double? popularityScore,
    DateTime? publishedAt,
    String? artworkUrl,
    String? playableUrl,
    String? previewUrl,
    bool? isDownloadable,
    String? audioFormat,
    String? bitrate,
    Map<String, dynamic>? providerMetadata,
    List<SearchProviderType>? matchedProviders,
  }) {
    return SearchCandidate(
      canonicalId: canonicalId ?? this.canonicalId,
      youtubeId: youtubeId ?? this.youtubeId,
      audiusId: audiusId ?? this.audiusId,
      jamendoId: jamendoId ?? this.jamendoId,
      jioSaavnId: jioSaavnId ?? this.jioSaavnId,
      spotifyId: spotifyId ?? this.spotifyId,
      deezerId: deezerId ?? this.deezerId,
      isrc: isrc ?? this.isrc,
      musicBrainzId: musicBrainzId ?? this.musicBrainzId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      channelOrOwner: channelOrOwner ?? this.channelOrOwner,
      normalizedTitle: normalizedTitle ?? this.normalizedTitle,
      normalizedArtist: normalizedArtist ?? this.normalizedArtist,
      normalizedAlbum: normalizedAlbum ?? this.normalizedAlbum,
      duration: duration ?? this.duration,
      language: language ?? this.language,
      region: region ?? this.region,
      versionType: versionType ?? this.versionType,
      sourceProvider: sourceProvider ?? this.sourceProvider,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      popularityScore: popularityScore ?? this.popularityScore,
      publishedAt: publishedAt ?? this.publishedAt,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      playableUrl: playableUrl ?? this.playableUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      isDownloadable: isDownloadable ?? this.isDownloadable,
      audioFormat: audioFormat ?? this.audioFormat,
      bitrate: bitrate ?? this.bitrate,
      providerMetadata: providerMetadata ?? this.providerMetadata,
      matchedProviders: matchedProviders ?? this.matchedProviders,
    );
  }

  /// Converts this SearchCandidate to standard Domain `Song`
  Song toSong() {
    return Song(
      id: canonicalId,
      title: title,
      artist: artist,
      albumArt: artworkUrl,
      album: album,
      duration: duration,
      youtubeUrl: youtubeId != null ? 'https://www.youtube.com/watch?v=$youtubeId' : null,
      deezerUrl: deezerId,
      previewUrl: previewUrl ?? playableUrl,
      language: language,
      isYoutubeImport: youtubeId != null || sourceProvider == SearchProviderType.youtube,
      bitrate: bitrate,
      formatId: audioFormat,
    );
  }

  /// Converts this SearchCandidate to `SongModel`
  SongModel toSongModel() {
    return SongModel(
      id: canonicalId,
      title: title,
      artist: artist,
      albumArt: artworkUrl,
      album: album,
      duration: duration,
      youtubeUrl: youtubeId != null ? 'https://www.youtube.com/watch?v=$youtubeId' : null,
      deezerUrl: deezerId,
      previewUrl: previewUrl ?? playableUrl,
      language: language,
      isYoutubeImport: youtubeId != null || sourceProvider == SearchProviderType.youtube,
      bitrate: bitrate,
      formatId: audioFormat,
    );
  }

  /// Creates a canonical candidate from an existing Domain Song
  factory SearchCandidate.fromSong(Song song, {SearchProviderType provider = SearchProviderType.local}) {
    return SearchCandidate(
      canonicalId: song.id,
      youtubeId: song.youtubeUrl != null ? extractYtId(song.youtubeUrl!) : (song.id.startsWith('yt_') ? song.id.substring(3) : null),
      deezerId: song.deezerUrl,
      title: song.title,
      artist: song.artist,
      album: song.album,
      normalizedTitle: song.title.toLowerCase().trim(),
      normalizedArtist: song.artist.toLowerCase().trim(),
      normalizedAlbum: song.album?.toLowerCase().trim(),
      duration: song.duration,
      language: song.language,
      sourceProvider: provider,
      artworkUrl: song.albumArt,
      playableUrl: song.previewUrl,
      previewUrl: song.previewUrl,
      bitrate: song.bitrate,
      audioFormat: song.formatId,
      isDownloadable: true,
      matchedProviders: [provider],
    );
  }

  static String? extractYtId(String url) {
    final regExp = RegExp(r'(?:watch\?v=|youtu\.be\/|shorts\/|embed\/|v\/)([a-zA-Z0-9_\-]{11})');
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }
}

/// Request parameters sent to the search pipeline
@immutable
class SearchRequest {
  final String query;
  final int page;
  final int limit;
  final String? language;
  final String? region;
  final TrackVersionType? preferredVersion;
  final bool enableDeduplication;
  final bool enableDiversification;
  final bool enablePersonalization;
  final Set<SearchProviderType> enabledProviders;

  const SearchRequest({
    required this.query,
    this.page = 1,
    this.limit = 30,
    this.language,
    this.region,
    this.preferredVersion,
    this.enableDeduplication = true,
    this.enableDiversification = true,
    this.enablePersonalization = true,
    this.enabledProviders = const {
      SearchProviderType.local,
      SearchProviderType.jiosaavn,
      SearchProviderType.audius,
      SearchProviderType.jamendo,
      SearchProviderType.deezer,
      SearchProviderType.youtube,
      SearchProviderType.spotify,
      SearchProviderType.mongodb,
    },
  });
}

/// Feature vector computed for each candidate during ranking
@immutable
class RankingFeatures {
  final double textRelevance; // 0.0 - 1.0 (Exact title, similarity, artist match, n-gram, token overlap)
  final double popularity;    // 0.0 - 1.0 (log-scaled view count / stream popularity)
  final double userAffinity;   // 0.0 - 1.0 (LocalTasteEngine transitions, favorites, play frequency)
  final double freshness;      // 0.0 - 1.0 (Exponential age decay by category)
  final double trend;          // 0.0 - 1.0 (Recent play velocity)
  final double intentMatch;    // 0.0 - 1.0 (Aligns with song/artist/album/live query intent)
  final double languageMatch;  // 0.0 - 1.0 (Matches requested/detected language)
  final double versionMatch;   // 0.0 - 1.0 (Matches requested version: official/remix/live/acoustic)
  final double exactBoost;     // Positive boost factor for exact match
  final double penalty;        // Negative penalty factor for reaction/unrelated/garbage

  const RankingFeatures({
    this.textRelevance = 0.0,
    this.popularity = 0.0,
    this.userAffinity = 0.0,
    this.freshness = 0.0,
    this.trend = 0.0,
    this.intentMatch = 0.0,
    this.languageMatch = 0.0,
    this.versionMatch = 0.0,
    this.exactBoost = 0.0,
    this.penalty = 0.0,
  });

  /// Computes final composite score using Aura Ranking Weights:
  /// TextRelevance * 0.42 + Popularity * 0.14 + UserAffinity * 0.15 + Freshness * 0.08 +
  /// Trend * 0.07 + IntentMatch * 0.06 + LanguageMatch * 0.04 + VersionMatch * 0.04 + exactBoost - penalty
  double computeScore() {
    double score = (textRelevance * 0.42) +
        (popularity * 0.14) +
        (userAffinity * 0.15) +
        (freshness * 0.08) +
        (trend * 0.07) +
        (intentMatch * 0.06) +
        (languageMatch * 0.04) +
        (versionMatch * 0.04) +
        exactBoost -
        penalty;

    return score.clamp(0.0, 1.0);
  }
}

/// Ranked Candidate with score and breakdown explanation
@immutable
class RankedCandidate {
  final SearchCandidate candidate;
  final double finalScore;
  final RankingFeatures features;
  final String? rankingExplanation;

  const RankedCandidate({
    required this.candidate,
    required this.finalScore,
    required this.features,
    this.rankingExplanation,
  });
}

/// Final Output Response from Search Pipeline
@immutable
class SearchResponse {
  final String rawQuery;
  final ParsedQuery parsedQuery;
  final List<RankedCandidate> rankedResults;
  final List<Song> songs;
  final String? didYouMean;
  final List<String> autocompleteSuggestions;
  final Duration totalLatency;
  final Map<SearchProviderType, Duration> providerLatencies;
  final Map<SearchProviderType, int> providerCandidateCounts;
  final Map<SearchProviderType, String> providerErrors;
  final bool isFromCache;
  final bool isOfflineFallback;

  const SearchResponse({
    required this.rawQuery,
    required this.parsedQuery,
    required this.rankedResults,
    required this.songs,
    this.didYouMean,
    this.autocompleteSuggestions = const [],
    required this.totalLatency,
    this.providerLatencies = const {},
    this.providerCandidateCounts = const {},
    this.providerErrors = const {},
    this.isFromCache = false,
    this.isOfflineFallback = false,
  });
}
