# 🎵 Aura Player — Complete Technical Architecture & Production Manual

> **Aura Player** (`free_play`) is an ad-free, offline-first music streaming, discovery, and secure peer-to-peer communication application built with Flutter, Riverpod, Just Audio, Hive, Node.js microservices, and a Decoupled Dual-Database Cloud Firestore architecture.

---

## 📑 Table of Contents
1. [Project Overview](#1-project-overview)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Folder Structure](#3-folder-structure)
4. [Flutter App Architecture](#4-flutter-app-architecture)
5. [Search Architecture](#5-search-architecture)
6. [Search Pipeline](#6-search-pipeline)
7. [Provider List](#7-provider-list)
8. [Provider Responsibilities](#8-provider-responsibilities)
9. [Ranking Pipeline](#9-ranking-pipeline)
10. [Ranking Formula](#10-ranking-formula)
11. [Deduplication Strategy](#11-deduplication-strategy)
12. [Personalization Strategy](#12-personalization-strategy)
13. [Autocomplete Engine](#13-autocomplete-engine)
14. [Offline-First Behavior](#14-offline-first-behavior)
15. [Cache Behavior & Hierarchy](#15-cache-behavior--hierarchy)
16. [Quota Management](#16-quota-management)
17. [Backend Architecture](#17-backend-architecture)
18. [YouTube API Integration & Security](#18-youtube-api-integration--security)
19. [MongoDB Atlas Search Configuration](#19-mongodb-atlas-search-configuration)
20. [Firebase & Firestore Configuration](#20-firebase--firestore-configuration)
21. [Environment Variables](#21-environment-variables)
22. [Local Setup](#22-local-setup)
23. [Backend Setup](#23-backend-setup)
24. [Android Build Guide](#24-android-build-guide)
25. [Testing Suite](#25-testing-suite)
26. [Deployment Guide](#26-deployment-guide)
27. [Troubleshooting & Diagnostics](#27-troubleshooting--diagnostics)
28. [Human / Manual Steps](#28-human--manual-steps)
29. [Known Limitations](#29-known-limitations)
30. [Cost & Free-Tier Assumptions](#30-cost--free-tier-assumptions)
31. [Provider Policy & Licensing Cautions](#31-provider-policy--licensing-cautions)
32. [HUMAN ACTION REQUIRED Document](#32-human-action-required-document)

---

## 1. Project Overview
Aura Player is an offline-first music streaming and discovery application engineered for zero audio latency, resilient multi-provider candidate retrieval, and uncompromised privacy. It features:
- **Universal Multi-Provider Music Engine**: Retrieves search candidates concurrently across 8 sources (Local Storage, JioSaavn, Audius, Jamendo, Deezer, YouTube Data API backend proxy, Spotify, MongoDB Atlas Search).
- **Aura Relevance & Ranking Pipeline**: A unified, provider-independent ranking formula combining Text Relevance (0.42), Popularity (0.14), User Affinity (0.15), Freshness (0.08), Trend (0.07), Intent (0.06), Language (0.04), and Version (0.04).
- **Query Intelligence**: Devanagari & Bengali multilingual transliteration, spell correction, deterministic semantic entity extraction, and version intent classification.
- **Audio Extraction & Multi-Tier Download**: Offline download with format choices (High ~320kbps, Medium ~128kbps, Data Saver ~64kbps).
- **Decoupled Dual-Database Architecture**: Isolated primary Firestore DB for app config and user metadata, alongside an entirely separate database instance (`databaseId: 'chat'`) for private ephemeral direct messaging.

---

## 2. Architecture Diagram

```
                              ┌────────────────────────────────────────────────────────┐
                              │                     AURA PLAYER UI                     │
                              │     (SearchScreen, FullPlayer, MiniPlayer, Console)    │
                              └───────────────────────────┬────────────────────────────┘
                                                          │
                                                [ User Query Input ]
                                                          │
                                                          ▼
                                            ┌───────────────────────────┐
                                            │     QUERY INTELLIGENCE    │
                                            │ • QueryNormalizer (NFKD)  │
                                            │ • SpellCorrector          │
                                            │ • TransliterationEngine   │
                                            │ • QueryIntentDetector     │
                                            │ • EntityExtractor         │
                                            └─────────────┬─────────────┘
                                                          │ ParsedQuery
                                                          ▼
                                            ┌───────────────────────────┐
                                            │     SEARCH CACHE (L2)     │
                                            │  Key: query|intent|lang   │
                                            └──────┬─────────────┬──────┘
                                    Cache HIT      │             │ Cache MISS
                                  ┌────────────────┘             └────────────────┐
                                  ▼                                               ▼
                    ┌───────────────────────────┐                   ┌───────────────────────────┐
                    │      CACHED RESPONSE      │                   │    CANDIDATE RETRIEVER    │
                    │   (Fast Zero-Cost Path)   │                   │ (Parallel Resilient Pool) │
                    └─────────────┬─────────────┘                   └─────────────┬─────────────┘
                                  │                                               │
                                  │       ┌─────────────────┬─────────────────┬───┴─────────────┬─────────────────┐
                                  │       ▼                 ▼                 ▼                 ▼                 ▼
                                  │   [ Local Hive ]   [ JioSaavn ]      [ Audius ]        [ Jamendo ]       [ Deezer ]
                                  │   (Offline Songs)  (Stream API)     (Discovery API)   (CC Open Music)   (30s Preview)
                                  │       │                 │                 │                 │                 │
                                  │       ├─────────────────┴─────────────────┼─────────────────┴─────────────────┤
                                  │       ▼                                   ▼                                   ▼
                                  │   [ YouTube Proxy ]               [ Spotify API ]                    [ MongoDB Atlas ]
                                  │   (Backend Server)                (Metadata Only)                    (Lucene Search)
                                  │       │                                   │                                   │
                                  │       └─────────────────┬─────────────────┴───────────────────────────────────┘
                                  │                         │ SearchCandidate Stream
                                  │                         ▼
                                  │           ┌───────────────────────────┐
                                  │           │      CANDIDATE MERGER     │
                                  │           │ • Hard Irrelevant Filter  │
                                  │           │ • Shorts/Reaction Filter  │
                                  │           └─────────────┬─────────────┘
                                  │                         │
                                  │                         ▼
                                  │           ┌───────────────────────────┐
                                  │           │    CANONICAL DEDUP (L3)   │
                                  │           │ • ISRC Match              │
                                  │           │ • MusicBrainz Match       │
                                  │           │ • Title+Artist+Duration   │
                                  │           └─────────────┬─────────────┘
                                  │                         │
                                  │                         ▼
                                  │           ┌───────────────────────────┐
                                  │           │   AURA RELEVANCE RANKER   │
                                  │           │ • Text Relevance (0.42)   │
                                  │           │ • Popularity Log (0.14)   │
                                  │           │ • Local Taste (0.15)      │
                                  │           │ • Freshness Decay (0.08)  │
                                  │           │ • Exact Match Boost       │
                                  │           │ • Noise Penalties         │
                                  │           └─────────────┬─────────────┘
                                  │                         │
                                  │                         ▼
                                  │           ┌───────────────────────────┐
                                  │           │    RESULT DIVERSIFIER     │
                                  │           │ • Max 4 songs/artist      │
                                  │           │ • Mix Official/Live/Remix │
                                  │           └─────────────┬─────────────┘
                                  │                         │
                                  └────────────────► ◄──────┘
                                                     │
                                                     ▼
                                      ┌───────────────────────────┐
                                      │   SEARCH RESPONSE PACKET  │
                                      │ • Ranked Results List     │
                                      │ • Did You Mean Suggestion │
                                      │ • Autocomplete Index      │
                                      │ • Realtime Telemetry      │
                                      └───────────────────────────┘
```

---

## 3. Folder Structure

```
free_play/
├── .env.example                                  # Sanitized environment variable template
├── pubspec.yaml                                  # Flutter dependencies & assets configuration
├── functions/                                    # Firebase Cloud Functions (Node.js/TypeScript)
├── youtube-extractor-microservice/               # Backend microservice (yt-dlp, YouTube API proxy)
│   ├── server.js                                 # Express server with /api/search and /api/youtube
│   └── package.json
├── test/
│   ├── fixtures/
│   │   └── search_ranking_cases.json             # 100+ Golden test cases across multiple languages
│   ├── core/search/
│   │   ├── query_intelligence_test.dart          # Normalization, Spell, Intent, Transliteration tests
│   │   ├── ranking_pipeline_test.dart            # Similarity, Exact Match Boost & Score bounds tests
│   │   ├── deduplication_and_diversity_test.dart # Canonical resolver & diversifier tests
│   │   ├── circuit_breaker_and_quota_test.dart   # Circuit breaker state & Quota store tests
│   │   ├── autocomplete_and_cache_test.dart      # Autocomplete Trie & cache key tests
│   │   └── golden_ranking_cases_test.dart        # Full 100+ query golden test runner
│   ├── playlist_offline_and_mix_test.dart
│   └── search_failover_test.dart
└── lib/
    ├── main.dart                                 # Application entry point
    ├── core/
    │   ├── constants/                            # App colors, styles, dimensions
    │   ├── search/                               # Core Search Architecture
    │   │   ├── models/
    │   │   │   └── search_models.dart            # Canonical SearchCandidate, ParsedQuery, SearchRequest
    │   │   ├── query/
    │   │   │   ├── query_intelligence.dart       # Query intelligence orchestrator
    │   │   │   ├── query_normalizer.dart         # NFKD, whitespace, punctuation, repetition compression
    │   │   │   ├── spell_corrector.dart          # Dictionary, aliases, and trained corrections
    │   │   │   ├── query_intent_detector.dart    # Intent detection with word boundaries
    │   │   │   ├── query_expander.dart           # Synonym & transliteration expander
    │   │   │   ├── transliteration_engine.dart   # Indic (Hindi/Bengali) <-> Latin transliteration
    │   │   │   └── entity_extractor.dart         # Deterministic entity extraction
    │   │   ├── providers/
    │   │   │   ├── search_provider.dart          # SearchProviderClient interface
    │   │   │   ├── provider_health.dart          # ProviderHealth & CircuitBreaker state
    │   │   │   ├── local_search_provider.dart    # Offline songs, playlists, recently played
    │   │   │   ├── audius_search_provider.dart   # Audius decentralized API client
    │   │   │   ├── jamendo_search_provider.dart  # Jamendo CC music client
    │   │   │   ├── jiosaavn_search_provider.dart # JioSaavn audio streaming client
    │   │   │   ├── deezer_search_provider.dart   # Deezer metadata & preview client
    │   │   │   ├── youtube_search_provider.dart  # Backend YouTube Data API proxy client
    │   │   │   ├── spotify_search_provider.dart  # Spotify metadata discovery client
    │   │   │   └── mongodb_search_provider.dart  # MongoDB Atlas Lucene search client
    │   │   ├── ranking/
    │   │   │   ├── string_similarity.dart        # Levenshtein, Jaro-Winkler, N-gram Dice, Jaccard
    │   │   │   ├── ranking_features.dart         # Feature vector definitions
    │   │   │   ├── feature_extractor.dart        # Extracts scoring features against ParsedQuery
    │   │   │   ├── score_policy.dart             # Configurable ranking formula weights
    │   │   │   ├── score_boosts.dart             # Exact title/artist/phrase boosts
    │   │   │   ├── score_penalties.dart          # Reaction/shorts/unrelated demotions
    │   │   │   └── aura_search_ranker.dart       # Core Aura Ranking Engine
    │   │   ├── dedup/
    │   │   │   ├── canonical_track_resolver.dart # Cross-provider identity resolver
    │   │   │   └── search_deduplicator.dart      # Multi-provider candidate merger
    │   │   ├── diversity/
    │   │   │   └── result_diversifier.dart       # Anti-clustering & version balancer
    │   │   ├── autocomplete/
    │   │   │   ├── autocomplete_index.dart       # High-speed in-memory prefix Trie
    │   │   │   ├── autocomplete_engine.dart      # Realtime local suggestions engine
    │   │   │   └── did_you_mean_engine.dart      # Typo suggestion generator
    │   │   ├── cache/
    │   │   │   ├── search_cache_key.dart         # Composite structured cache key
    │   │   │   └── search_cache.dart             # Hive-backed LRU/TTL search cache
    │   │   ├── quota/
    │   │   │   ├── provider_quota.dart           # Daily quota tracking & request costs
    │   │   │   ├── quota_store.dart              # Persistent quota storage
    │   │   │   └── quota_manager.dart            # Quota gatekeeper
    │   │   ├── health/
    │   │   │   ├── circuit_breaker.dart          # Resilient execution wrapper
    │   │   │   └── provider_health_monitor.dart  # Realtime provider diagnostics monitor
    │   │   ├── pipeline/
    │   │   │   ├── candidate_retriever.dart      # Parallel provider execution pool
    │   │   │   ├── candidate_merger.dart         # Hard filtering and candidate consolidation
    │   │   │   └── search_pipeline.dart          # Master search pipeline coordinator
    │   │   └── telemetry/
    │   │       ├── search_metrics.dart           # Console & analytics logger
    │   │       └── search_diagnostics.dart       # Developer/admin telemetry snapshots
    ├── data/
    │   ├── models/                               # Data models (SongModel, UserModel, RoomModel)
    │   └── services/                             # AudioService, LocalTasteEngine, DirectJioSaavnService
    ├── domain/
    │   └── entities/                             # Song, Playlist, ChatMessage domain entities
    └── presentation/
        ├── providers/                            # Riverpod state providers (searchFailoverProvider)
        ├── screens/                              # SearchScreen, FullPlayer, MainScreen, SecretConsole
        └── widgets/                              # SongTile, FullPlayer, SkeletonShimmer
```

---

## 4. Flutter App Architecture
The client application leverages Flutter Riverpod with Clean Architecture principles:
- **Presentation Layer**: Stateful widgets decoupled from networking logic. Reactive state watched via Riverpod Notifiers.
- **Domain Layer**: Immutable business models (`Song`, `SearchCandidate`, `ParsedQuery`).
- **Data Layer**: High-speed local persistence using Hive boxes, combined with Dio HTTP clients and background audio isolates (`just_audio`, `audio_service`).

---

## 5. Search Architecture
Search is architected around the **Candidate Retrieval & Ranking** paradigm:
1. **Decoupled Retrieval vs Ranking**: Retrieval providers fetch candidates independently. A provider's internal rank never dictates the application's final order.
2. **Provider Independence**: External JSON responses are immediately transformed into canonical `SearchCandidate` domain instances.
3. **Resilience & Circuit Breakers**: If a remote provider times out (e.g. 4s) or returns 429/500 errors 5 consecutive times, its circuit trips to `OPEN`, immediately shielding subsequent searches from latency penalties until the 30-second cooldown expires.

---

## 6. Search Pipeline
When a user types in the search box:
1. **Debounce (300ms)**: Cancels intermediate keystrokes. Instant local autocomplete suggestions fire concurrently from the in-memory Trie index (<50ms).
2. **Query Intelligence**: Normalizes text, corrects spelling, resolves Indic script transliterations (Devanagari/Bengali), detects query intent (`song`, `artist`, `album`, `live`, `remix`, `slowed`, `acoustic`), and extracts semantic entities.
3. **Cache Lookup**: Checks the composite key `normalizedQuery|intent|language|region` in Hive. On a HIT, cached results are returned instantly (0 network cost).
4. **Candidate Retrieval**: On a cache MISS, enabled providers are queried in parallel with bounded timeouts (Local, JioSaavn, Audius, Jamendo, Deezer, YouTube Backend Proxy, Spotify, MongoDB).
5. **Candidate Merge & Hard Filtering**: Drops irrelevant results (reactions, podcasts, gameplay, trailers) unless explicitly requested.
6. **Canonical Deduplication**: Merges tracks across providers by matching ISRC, MusicBrainz IDs, or Title + Artist + Duration.
7. **Aura Relevance Ranking**: Scores candidates using the Aura Ranking Formula.
8. **Result Diversification**: Prevents single-artist saturation and interleaves song versions.
9. **Cache Write & Output**: Top results are persisted to Hive and emitted to UI.

---

## 7. Provider List

| Priority | Provider | Type | Output Capability | Free Allowance / Limits |
|---|---|---|---|---|
| 1 | **Local Cache & Storage** | Local Hive | Full Offline Streaming & Download | Unlimited (Local On-Device) |
| 2 | **Audius** | Decentralized API | Full Track Streaming & Discovery | Free Tier (Host Discovery, ~10k req/day) |
| 3 | **Jamendo** | Open CC API | Free CC Streaming & Download | Free Tier (Client ID required, ~10k req/day) |
| 4 | **JioSaavn** | Stream API | Full Track Streaming (320kbps) | Unofficial Web API (Protected with Circuit Breaker) |
| 5 | **Deezer** | Preview/Meta API | 30s High-Quality MP3 Preview & Meta | Free Tier (~50 req/5s rate limit) |
| 6 | **YouTube** | Backend Data API Proxy | Full Search & yt-dlp Extraction | 10,000 units/day (100 units per search.list) |
| 7 | **Spotify** | Web API | Rich Metadata & Recommendations | Free Developer Tier (Client Credentials) |
| 8 | **MongoDB Atlas** | Lucene Search | Aura Owned Indexed Metadata | Free M0 Cluster (512MB storage) |

---

## 8. Provider Responsibilities
- **Local**: Instantly surfaces downloaded tracks, user playlist songs, and cached history without network access.
- **Audius**: Provides legal independent and electronic music streaming with no user authentication required.
- **Jamendo**: Delivers open-license Creative Commons tracks and verifies `audiodownload_allowed` before enabling offline downloads.
- **JioSaavn**: Provides rich Bollywood, regional Indian, and global pop audio streams with dynamic authentication token generation.
- **Deezer**: Acts as a metadata enricher and instant 30-second preview provider.
- **YouTube (Backend)**: Operates server-side through `youtube-extractor-microservice` to protect API keys, providing YouTube Data API v3 search with yt-dlp fallback.
- **Spotify**: Supplies album artwork, track popularity ratings, and recommendation seed vectors.
- **MongoDB Atlas**: Runs full-text Lucene autocomplete and fuzzy search on Aura's own indexed song catalogue.

---

## 9. Ranking Pipeline
All retrieved candidates flow through a single ranking engine:
- **Normalization**: Every candidate string and query term is stripped of punctuation, accents, and case differences.
- **Feature Vector Extraction**: Features (`textRelevance`, `popularity`, `userAffinity`, `freshness`, `trend`, `intentMatch`, `languageMatch`, `versionMatch`, `exactBoost`, `penalty`) are extracted into `RankingFeatures`.
- **Composite Score Calculation**: Evaluates the formula and clamps the score between `0.0` and `1.0`.

---

## 10. Ranking Formula

$$\text{FinalScore} = \sum (\text{Feature}_i \times \text{Weight}_i) + \text{ExactBoost} - \text{Penalty}$$

### Configurable Weights:
- **Text Relevance**: `0.42`
  - Exact Title Match: `0.35`
  - Title Similarity (Levenshtein + Jaro-Winkler): `0.20`
  - Artist Match: `0.15`
  - Token Overlap (Jaccard): `0.10`
  - N-gram Dice Similarity: `0.10`
  - Album Match: `0.05`
- **Popularity** (Log-scaled): `0.14`
- **User Taste & Affinity** (`LocalTasteEngine`): `0.15`
- **Freshness** (Exponential age decay): `0.08`
- **Trend Velocity**: `0.07`
- **Intent Alignment**: `0.06`
- **Language Match**: `0.04`
- **Version Match**: `0.04`

---

## 11. Deduplication Strategy
Candidate tracks are resolved into one logical song entity by `CanonicalTrackResolver`:
1. **ISRC Match**: Exact 12-character international recording code.
2. **MusicBrainz Identifier**: Recording/Release UUID cross-reference.
3. **Normalized Title + Normalized Artist + Duration Bucket**: Matches tracks when artist is identical and duration is within $\pm 12$ seconds.
4. **Different Artist Protection**: Tracks with the same title by different artists (e.g. *"Perfect"* by Ed Sheeran vs *"Perfect"* by Simple Plan) are **never** merged.

---

## 12. Personalization Strategy
Driven by the 100% on-device `LocalTasteEngine`:
- **Transition Matrix**: Tracks transitions from song A to song B.
- **Favorite Artists & Playlists**: Applies bounded affinity boost (+1.5 for top 10 played artists, +3.0 for favorite playlist songs).
- **Critical Safety Guard**: Personalization only re-orders relevant candidates. It can never promote an irrelevant song to #1.

---

## 13. Autocomplete Engine
- **In-Memory Prefix Trie (`AutocompleteIndex`)**: Stores recent searches, favorite artists, top songs, and seed queries.
- **Instant Response**: Evaluates local Trie queries in under 50ms without initiating external API calls.
- **"Did You Mean?" Engine**: Checks queries against typo dictionaries, Indic transliterations, and trained synonyms, displaying formatted suggestion banners for misspelled queries.

---

## 14. Offline-First Behavior
When network connectivity is unavailable:
- Search automatically runs against Local Hive Cache (`offline_songs`, `recentlyPlayed`, `userPlaylists`).
- Search UI displays a subtle offline banner without throwing fatal connection errors.
- Songs stored locally remain 100% playable.

---

## 15. Cache Behavior & Hierarchy
- **L1 Cache**: In-memory prefix Trie for autocomplete suggestions.
- **L2 Cache**: Hive Box `aura_search_cache_v2` with LRU eviction (max 200 queries) and 24-hour TTL.
- **L3 Cache**: Offline downloaded tracks stored in `offline_songs` box with file path bindings.

---

## 16. Quota Management
`QuotaManager` enforces client-side and server-side rate-limiting:
- **YouTube Data API**: 10,000 quota units/day (100 units/search). Avoids duplicate queries and stops additional calls when confident local results exist.
- **Audius & Jamendo**: 10,000 requests/day bucket.
- **JioSaavn**: Rate-limit protection with 5s timeout and circuit breaker fallback.

---

## 17. Backend Architecture
The backend microservice (`youtube-extractor-microservice/server.js`) runs an Express server:
- **Endpoint 1: `GET /api/search/youtube`**: Executes YouTube Data API v3 searches server-side, falling back to `yt-dlp --flat-playlist` and JioSaavn fallback.
- **Endpoint 2: `POST /api/youtube/extract`**: Multi-format audio stream extraction (High 320kbps, Medium 128kbps, Low 64kbps).
- **Endpoint 3: `GET /api/youtube/download`**: Streams audio binaries directly with intact audio container headers.
- Every yt-dlp invocation uses `cookies.txt` when available. The file is generated from `YOUTUBE_COOKIES_BASE64` at startup or can be supplied locally for development.

---

## 18. YouTube API Integration & Security
> [!IMPORTANT]
> **API Key Protection**: YouTube API keys must **NEVER** be committed into git or hardcoded into Flutter client source code.
- Keys are loaded from `process.env.YOUTUBE_API_KEY` on the backend server only.
- Client requests go through the backend `/api/search/youtube` proxy.
- YouTube session cookies are loaded from `process.env.YOUTUBE_COOKIES_BASE64` and written to the ignored `youtube-extractor-microservice/cookies.txt` file at startup.
- `/health` exposes `youtubeCookiesConfigured: true|false`; it never returns cookie data.

---

## 19. MongoDB Atlas Search Configuration
For Aura-owned catalog indexing on MongoDB Atlas M0 cluster:
- **Database**: `aura_music`
- **Collection**: `songs`
- **Search Index Name**: `search_index`

### Atlas Search Index Definition (JSON):
```json
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": [
        {
          "type": "autocomplete",
          "analyzer": "lucene.standard",
          "tokenization": "edgeGram",
          "minGrams": 2,
          "maxGrams": 15
        },
        {
          "type": "string",
          "analyzer": "lucene.standard"
        }
      ],
      "artist": [
        {
          "type": "autocomplete",
          "analyzer": "lucene.standard",
          "tokenization": "edgeGram",
          "minGrams": 2,
          "maxGrams": 15
        },
        {
          "type": "string",
          "analyzer": "lucene.standard"
        }
      ],
      "album": {
        "type": "string",
        "analyzer": "lucene.standard"
      },
      "popularity": {
        "type": "number"
      }
    }
  }
}
```

---

## 20. Firebase & Firestore Configuration
- **Primary Database**: `(default)` — User profiles, system configuration, public playlists.
- **Chat Database**: `databaseId: 'chat'` — Strictly isolated database instance for encrypted direct messaging and room handshakes. Do NOT merge this database.

---

## 21. Environment Variables
Reference `.env.example` for all configurable keys. Never commit `.env`, `cookies.txt`, or exported browser cookies into git.

The YouTube extractor accepts these backend variables:

| Variable | Required | Description |
|---|---:|---|
| `PORT` | No | HTTP port; defaults to `3000`. |
| `YOUTUBE_API_KEY` | No | Server-side YouTube Data API v3 key used for search. |
| `YOUTUBE_COOKIES_BASE64` | No | Base64-encoded Netscape-format YouTube `cookies.txt` content for yt-dlp authentication. |

---

## 22. Local Setup
1. Clone the repository.
2. Run Flutter dependencies:
   ```bash
   flutter pub get
   ```
3. Copy `.env.example` to `.env` and fill in necessary configuration parameters.

---

## 23. Backend Setup
1. Navigate to `youtube-extractor-microservice`:
   ```bash
   cd youtube-extractor-microservice
   npm install
   ```
2. Start the server:
   ```bash
   npm start
   ```
3. For local YouTube extraction, place an exported Netscape-format `cookies.txt` in this directory, or set `YOUTUBE_COOKIES_BASE64` before starting the service:
  ```bash
  export YOUTUBE_COOKIES_BASE64="$(base64 -w 0 cookies.txt)"
  npm start
  ```
4. Verify the service and cookie status:
  ```bash
  curl http://localhost:3000/health
  ```
  The response should include `"youtubeCookiesConfigured":true` when cookies are available.

---

## 24. Android Build Guide
1. Ensure Android SDK 34+ and Flutter 3.x are installed.
2. Build debug APK:
   ```bash
   flutter build apk --debug
   ```
3. Build release APK:
   ```bash
   flutter build apk --release
   ```

---

## 25. Testing Suite
Run all automated tests:
```bash
flutter test
```
Run search-specific ranking and pipeline tests:
```bash
flutter test test/core/search
```

---

## 26. Deployment Guide
- **Backend Microservice**: Deploy `youtube-extractor-microservice` to Render, Railway, or Docker container. Configure `YOUTUBE_COOKIES_BASE64` as a secret environment variable when YouTube requires an authenticated session.
- **Firebase Functions**: Deploy via `firebase deploy --only functions`.
- **Flutter Client**: Distribute generated release APK or upload App Bundle to Google Play Console.

---

## 27. Troubleshooting & Diagnostics
- **Search returns empty**: Verify network connection and backend microservice health (`GET /health`).
- **Circuit Breaker tripped**: Check `ProviderHealthMonitor` diagnostics to inspect consecutive error reasons.
- **YouTube download failed**: Ensure `yt-dlp` binary on the backend server is updated to the latest release.
- **YouTube bot checks persist**: Confirm `/health` reports `youtubeCookiesConfigured:true`, verify the value is base64-encoded Netscape cookie content, and redeploy after updating the secret. Never paste raw cookie contents into logs or source control.

---

## 28. Human / Manual Steps
Certain actions cannot be performed autonomously by code and require manual web console configuration. See [Section 32: HUMAN ACTION REQUIRED Document](#32-human-action-required-document).

---

## 29. Known Limitations
- Spotify Web API provides 30-second previews and metadata only (no full audio streaming via Web API).
- Deezer API supports 30-second previews in non-partner regions.
- JioSaavn unofficial endpoints may experience temporary throttling if queried without debouncing.

---

## 30. Cost & Free-Tier Assumptions

| Service | Free Tier Allowance | Cost Risk |
|---|---|---|
| YouTube Data API v3 | 10,000 units/day free | Low (Free within daily quota) |
| Audius API | Unlimited open access | Zero |
| Jamendo API | Free Developer Tier | Zero |
| Spotify Web API | Free Developer Tier | Zero |
| MongoDB Atlas | M0 Cluster (512 MB storage) | Zero |
| Render Web Service | Free Tier (750 hours/month) | Zero |
| Firebase Firestore | Spark Plan (50k reads, 20k writes/day) | Zero |

---

## 31. Provider Policy & Licensing Cautions
- Do not permanently store or mirror copyright audio on public cloud buckets.
- Strictly adhere to Jamendo `audiodownload_allowed` flags for offline caching.
- Do not use Spotify metadata to train public machine learning models.

---

## 32. HUMAN ACTION REQUIRED Document

### A. ZERO-CODE / WEB CONSOLE ACTIONS
1. **Google Cloud Console**:
   - **WHERE**: https://console.cloud.google.com/apis/credentials
   - **WHAT TO CLICK**: Create Credentials → API Key
   - **WHAT TO CREATE**: Restrict key to *YouTube Data API v3*
   - **WHAT VALUE TO ENTER**: "Aura Player YouTube API Key"
   - **WHERE TO COPY**: Enter into backend `.env` as `YOUTUBE_API_KEY`
   - **SECRET**: YES (Server-side only)
   - **FREQUENCY**: Once

### B. MONGODB ATLAS ACTIONS
1. **MongoDB Atlas Console**:
   - **WHERE**: https://cloud.mongodb.com/ → Database → Browse Collections
   - **WHAT TO CLICK**: Search Indexes → Create Search Index → JSON Editor
   - **WHAT VALUE TO ENTER**: Paste JSON definition from Section 19
   - **INDEX NAME**: `search_index`
   - **FREQUENCY**: Once per cluster

### C. RENDER / BACKEND HOSTING ACTIONS
1. **Render Dashboard**:
   - **WHERE**: https://dashboard.render.com/
   - **WHAT TO CLICK**: New Web Service → Connect repository (`youtube-extractor-microservice`)
  - **ENVIRONMENT VARIABLES**: Set `PORT=3000`, `YOUTUBE_API_KEY=<key>`, and the secret `YOUTUBE_COOKIES_BASE64=<base64-cookie-content>`
  - **COOKIE PREPARATION**: Export YouTube cookies in Netscape `cookies.txt` format, then encode them locally with `base64 -w 0 cookies.txt` before adding the result to Render.
   - **FREQUENCY**: Once

### D. PHYSICAL ANDROID DEVICE TEST CHECKLIST
1. Install debug APK on physical Android device.
2. Search query: `"arjit tum hi ho"` → Verify Arijit Singh *Tum Hi Ho* appears at #1.
3. Search query: `"तुम ही हो"` (Hindi Devanagari) → Verify transliterated match.
4. Toggle Airplane mode → Perform search → Verify local offline search banner and playback.
5. Tap *Import Link* → Paste YouTube video link → Verify 3-tier format selection modal.
6. Tap hardware back button when search query is open → Verify search is cleared before navigating across tabs.
7. Connect USB DAC or Hi-Fi headphones → Verify Bit-Perfect badge displays live sample rate (e.g., `48.0 kHz / 24-bit` or `96.0 kHz`) and opens Audiophile modal.

---

## 33. Android 14+ Bit-Perfect Audio & Hardware Back Stack

- **Bit-Perfect Direct HAL Pipeline (`MIXER_BEHAVIOR_BIT_PERFECT`)**: On Android 14+ (API 34+), the audio stream communicates with `AudioManager.setPreferredMixerAttributes` via Kotlin MethodChannel `aura_player/bit_perfect` to bypass system-level software mixer, resampling, and volume compression.
- **Audiophile Sample Rate Telemetry**: Real-time display of sample rate (`44.1 kHz`, `48.0 kHz`, `96.0 kHz`, `192.0 kHz / MHz DSD`) and bit depth across Mini and Full Players.
- **Comprehensive Back Navigation Hierarchy**: Back presses gracefully dismiss active full player panels, search query/results, nested route stacks, open dialogs, and tab history in priority sequence.
