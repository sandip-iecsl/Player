# 📖 Aura Player (`free_play`) — Complete Technical Reference Manual (`SRC.md`)

> Detailed technical specification of the final codebase, architecture, provider data flows, query-intelligence pipeline, ranking formulas, deduplication rules, and deployment operations.

---

## 📑 Table of Contents
1. [Architecture & System Flow](#1-architecture--system-flow)
2. [Complete Final File Tree](#2-complete-final-file-tree)
3. [Search Pipeline & Important Classes](#3-search-pipeline--important-classes)
4. [Class Responsibilities](#4-class-responsibilities)
5. [Search Data Flow](#5-search-data-flow)
6. [Provider Data Flow](#6-provider-data-flow)
7. [Query Intelligence Flow](#7-query-intelligence-flow)
8. [Ranking Formula & Feature Calculations](#8-ranking-formula--feature-calculations)
9. [Deduplication & Canonical Track Resolution](#9-deduplication--canonical-track-resolution)
10. [Result Diversification](#10-result-diversification)
11. [Autocomplete & "Did You Mean?" Engine](#11-autocomplete--did-you-mean-engine)
12. [Search Cache & Hierarchy](#12-search-cache--hierarchy)
13. [Quota Management & Rate Limiting](#13-quota-management--rate-limiting)
14. [Circuit Breakers & Provider Health Monitoring](#14-circuit-breakers--provider-health-monitoring)
15. [Database Architecture & Isolation](#15-database-architecture--isolation)
16. [Backend Microservice Endpoints](#16-backend-microservice-endpoints)
17. [Environment Variables](#17-environment-variables)
18. [Test Architecture & Verification](#18-test-architecture--verification)
19. [Failure & Recovery Behavior](#19-failure--recovery-behavior)
20. [Security Model](#20-security-model)
21. [HUMAN ACTION REQUIRED Document](#21-human-action-required-document)

---

## 1. Architecture & System Flow

Aura Player is structured around a decoupled Candidate-Retrieval & Ranking Architecture:

```
[ User Input Query ] ──► [ QueryIntelligence ] ──► [ Cache L2 Check ]
                                                            │
                                  ┌─────────────────────────┴─────────────────────────┐
                                  ▼ (Hit)                                             ▼ (Miss)
                          [ Return Cached ]                                  [ Parallel Candidate Pool ]
                                                                             ├── LocalSearchProvider
                                                                             ├── JioSaavnSearchProvider
                                                                             ├── AudiusSearchProvider
                                                                             ├── JamendoSearchProvider
                                                                             ├── DeezerSearchProvider
                                                                             ├── YouTubeSearchProvider (Backend)
                                                                             ├── SpotifySearchProvider
                                                                             └── MongoDBSearchProvider
                                                                                      │
                                                                                      ▼
                                                                             [ Candidate Merger & Filter ]
                                                                                      │
                                                                                      ▼
                                                                             [ Canonical Deduplicator ]
                                                                                      │
                                                                                      ▼
                                                                             [ Aura Relevance Ranker ]
                                                                                      │
                                                                                      ▼
                                                                             [ Result Diversifier ]
                                                                                      │
                                                                                      ▼
                                                                             [ Final SearchResponse ]
```

---

## 2. Complete Final File Tree

```
free_play/
├── .env.example
├── pubspec.yaml
├── README.md
├── SRC.md
├── youtube-extractor-microservice/
│   ├── Dockerfile
│   ├── package.json
│   ├── server.js
│   └── yt-dlp.exe
├── test/
│   ├── fixtures/
│   │   └── search_ranking_cases.json
│   ├── core/search/
│   │   ├── autocomplete_and_cache_test.dart
│   │   ├── circuit_breaker_and_quota_test.dart
│   │   ├── deduplication_and_diversity_test.dart
│   │   ├── golden_ranking_cases_test.dart
│   │   ├── query_intelligence_test.dart
│   │   └── ranking_pipeline_test.dart
│   ├── configuration_engine_test.dart
│   ├── playlist_offline_and_mix_test.dart
│   ├── search_failover_test.dart
│   └── youtube_quality_and_ranking_test.dart
└── lib/
    ├── main.dart
    ├── core/
    │   ├── search/
    │   │   ├── autocomplete/
    │   │   │   ├── autocomplete_engine.dart
    │   │   │   ├── autocomplete_index.dart
    │   │   │   └── did_you_mean_engine.dart
    │   │   ├── cache/
    │   │   │   ├── search_cache.dart
    │   │   │   └── search_cache_key.dart
    │   │   ├── dedup/
    │   │   │   ├── canonical_track_resolver.dart
    │   │   │   └── search_deduplicator.dart
    │   │   ├── diversity/
    │   │   │   └── result_diversifier.dart
    │   │   ├── health/
    │   │   │   ├── circuit_breaker.dart
    │   │   │   └── provider_health_monitor.dart
    │   │   ├── models/
    │   │   │   └── search_models.dart
    │   │   ├── pipeline/
    │   │   │   ├── candidate_merger.dart
    │   │   │   ├── candidate_retriever.dart
    │   │   │   └── search_pipeline.dart
    │   │   ├── providers/
    │   │   │   ├── audius_search_provider.dart
    │   │   │   ├── deezer_search_provider.dart
    │   │   │   ├── jamendo_search_provider.dart
    │   │   │   ├── jiosaavn_search_provider.dart
    │   │   │   ├── local_search_provider.dart
    │   │   │   ├── mongodb_search_provider.dart
    │   │   │   ├── provider_health.dart
    │   │   │   ├── search_provider.dart
    │   │   │   ├── spotify_search_provider.dart
    │   │   │   └── youtube_search_provider.dart
    │   │   ├── query/
    │   │   │   ├── entity_extractor.dart
    │   │   │   ├── query_expander.dart
    │   │   │   ├── query_intelligence.dart
    │   │   │   ├── query_intent_detector.dart
    │   │   │   ├── query_normalizer.dart
    │   │   │   ├── spell_corrector.dart
    │   │   │   └── transliteration_engine.dart
    │   │   ├── quota/
    │   │   │   ├── provider_quota.dart
    │   │   │   ├── quota_manager.dart
    │   │   │   └── quota_store.dart
    │   │   ├── ranking/
    │   │   │   ├── aura_search_ranker.dart
    │   │   │   ├── feature_extractor.dart
    │   │   │   ├── ranking_features.dart
    │   │   │   ├── score_boosts.dart
    │   │   │   ├── score_penalties.dart
    │   │   │   ├── score_policy.dart
    │   │   │   └── string_similarity.dart
    │   │   └── telemetry/
    │   │       ├── search_diagnostics.dart
    │   │       └── search_metrics.dart
    ├── data/
    │   ├── models/
    │   │   └── song_model.dart
    │   └── services/
    │       ├── audio_service.dart
    │       ├── direct_jiosaavn_service.dart
    │       ├── download_service.dart
    │       ├── hive_cache_manager.dart
    │       ├── hybrid_search_service.dart
    │       ├── local_taste_engine.dart
    │       ├── spotify_client_service.dart
    │       └── youtube_extractor_service.dart
    ├── domain/
    │   └── entities/
    │       └── song.dart
    └── presentation/
        ├── providers/
        │   ├── music_data_providers.dart
        │   └── search_failover_provider.dart
        └── screens/
            └── search_screen.dart
```

---

## 3. Search Pipeline & Important Classes

- `SearchPipeline` (`lib/core/search/pipeline/search_pipeline.dart`): Coordinates query intelligence, cache lookup, parallel candidate retrieval, candidate merging, deduplication, ranking, diversification, and telemetry logging.
- `CandidateRetriever` (`lib/core/search/pipeline/candidate_retriever.dart`): Issues concurrent bounded requests across all enabled search provider clients with individual timeout and quota checks.
- `AuraSearchRanker` (`lib/core/search/ranking/aura_search_ranker.dart`): Calculates composite feature vectors and ranks candidates using the Aura Ranking Formula.
- `SearchDeduplicator` (`lib/core/search/dedup/search_deduplicator.dart`): Merges duplicate candidate songs into a single canonical object.
- `CanonicalTrackResolver` (`lib/core/search/dedup/canonical_track_resolver.dart`): Resolves track equivalence by ISRC, MusicBrainz IDs, or Title + Artist + Duration.
- `QueryIntelligence` (`lib/core/search/query/query_intelligence.dart`): Transforms raw queries into `ParsedQuery`.

---

## 4. Class Responsibilities

| Class | Primary Responsibility |
|---|---|
| `SearchCandidate` | Canonical data transfer object unifying music metadata across all providers. |
| `ParsedQuery` | Structured semantic container for normalized text, detected intents, languages, and extracted entities. |
| `QueryNormalizer` | Normalizes diacritics, strips punctuation, collapses whitespace, and compresses character runs. |
| `SpellCorrector` | Resolves music typos against internal dictionary and Hive-persisted trained alias mappings. |
| `TransliterationEngine` | Transliterates Devanagari (Hindi) and Bengali script queries to searchable phonetic Latin representations. |
| `QueryIntentDetector` | Classifies query intent (`song`, `artist`, `album`, `live`, `remix`, `slowed`, `lofi`, `cover`, `acoustic`, `karaoke`, `discovery`). |
| `DeterministicEntityExtractor` | Extracts artist, title, album, year, and version modifiers without naive word splits. |
| `FeatureExtractor` | Computes the 10-dimensional feature vector for candidate scoring. |
| `ScoreBoosts` | Computes additive positive boosts for exact matches and intent alignments. |
| `ScorePenalties` | Subtracts penalties from irrelevant reactions, shorts, podcasts, or compilations. |
| `ResultDiversifier` | Interleaves track versions and caps artist clustering on the search results page. |
| `AutocompleteEngine` | In-memory prefix Trie providing instant (<50ms) search suggestions. |
| `DidYouMeanEngine` | Produces formatted typo suggestion strings when input differs from corrected query. |
| `SearchCache` | LRU and TTL managed search cache storing responses in Hive. |
| `QuotaManager` | Manages per-provider daily quotas and operation costs (e.g. YouTube search.list cost = 100). |
| `ProviderHealth` & `CircuitBreaker` | Tracks per-provider errors, timeouts, and manages CLOSED/OPEN/HALF_OPEN states. |

---

## 5. Search Data Flow

1. User types in `SearchScreen` TextField.
2. `SearchFailoverNotifier` debounces input for 300ms while Trie index emits instant autocomplete suggestions.
3. `SearchPipeline.execute()` receives `SearchRequest(query: query)`.
4. `QueryIntelligence.parse()` normalizes text, corrects typos, and extracts entities into `ParsedQuery`.
5. `SearchCache.get(key)` checks Hive. If found, returns cached candidate list immediately.
6. `CandidateRetriever.retrieve()` invokes `Local`, `JioSaavn`, `Audius`, `Jamendo`, `Deezer`, `YouTube (Backend)`, `Spotify`, and `MongoDB` concurrently.
7. `CandidateMerger.filterAndMerge()` drops noise (reactions, shorts, podcasts).
8. `SearchDeduplicator.deduplicate()` merges cross-provider duplicates.
9. `AuraSearchRanker.rank()` computes final composite scores.
10. `ResultDiversifier.diversify()` applies anti-clustering rules.
11. `SearchResponse` is emitted to UI and cached in Hive.

---

## 6. Provider Data Flow

```
External API / Service               Provider Client                  Internal DTO
──────────────────────────────────────────────────────────────────────────────────────────
Local Hive Storage             ──► LocalSearchProvider          ──► SearchCandidate
JioSaavn Direct API            ──► JioSaavnSearchProvider       ──► SearchCandidate
Audius Discovery Provider      ──► AudiusSearchProvider         ──► SearchCandidate
Jamendo v3.0 REST API          ──► JamendoSearchProvider        ──► SearchCandidate
Deezer Public Search API       ──► DeezerSearchProvider         ──► SearchCandidate
Node Backend /api/search       ──► YouTubeSearchProvider        ──► SearchCandidate
Spotify Client Credentials API ──► SpotifySearchProvider        ──► SearchCandidate
MongoDB Atlas Data API         ──► MongoDBSearchProvider        ──► SearchCandidate
```

---

## 7. Query Intelligence Flow

```
Raw Query: "arjit tum hi ho slowed reverb 2013"
   │
   ▼
[TransliterationEngine]: No Indic script detected -> "arjit tum hi ho slowed reverb 2013"
   │
   ▼
[QueryNormalizer]: NFKD normalize, lowercase, strip noise -> "arjit tum hi ho slowed reverb 2013"
   │
   ▼
[SpellCorrector]: "arjit" -> "arijit" -> "arijit tum hi ho slowed reverb 2013"
   │
   ▼
[QueryIntentDetector]: Regex matched "slowed|reverb" -> QueryIntent.slowed
   │
   ▼
[DeterministicEntityExtractor]:
   • Artist: "arijit singh"
   • Title: "tum hi ho"
   • Version: TrackVersionType.slowed
   • Year: 2013
   • Modifiers: ["slowed", "reverb"]
   │
   ▼
Output: ParsedQuery Object
```

---

## 8. Ranking Formula & Feature Calculations

$$\text{FinalScore} = (\text{TextRel} \times 0.42) + (\text{Pop} \times 0.14) + (\text{Affinity} \times 0.15) + (\text{Fresh} \times 0.08) + (\text{Trend} \times 0.07) + (\text{Intent} \times 0.06) + (\text{Lang} \times 0.04) + (\text{Ver} \times 0.04) + \text{ExactBoost} - \text{Penalty}$$

- **TextRelevance**:
  $$\text{TextRelevance} = (0.35 \times \text{ExactTitle}) + (0.20 \times \text{TitleSim}) + (0.15 \times \text{ArtistMatch}) + (0.10 \times \text{TokenOverlap}) + (0.10 \times \text{NGramDice}) + (0.05 \times \text{AlbumMatch})$$
- **Popularity**:
  $$\text{Popularity} = \frac{\log_{10}(\text{viewCount} + 1)}{10.0}$$
- **UserAffinity**:
  $$\text{UserAffinity} = \min\left(1.0, \frac{\text{LocalTasteEngine.getAffinityScore}}{15.0}\right)$$
- **Freshness**:
  $$\text{Freshness} = e^{-0.693 \times \frac{\text{ageInDays}}{180}}$$

---

## 9. Deduplication & Canonical Track Resolution

- **Rule 1**: If both items have valid `isrc` and `isrc_A == isrc_B`, they are merged into 1 canonical candidate.
- **Rule 2**: If both items have valid `musicBrainzId` and `mb_A == mb_B`, they are merged.
- **Rule 3**: If `artist_A` is identical to `artist_B` (or Levenshtein $\ge 0.80$) AND `title_A` matches `title_B` (or Levenshtein $\ge 0.85$) AND duration difference $\le 12\text{s}$, they are merged.
- **Rule 4 (Safety Rule)**: If artists differ (e.g. Ed Sheeran vs Simple Plan for *"Perfect"*), tracks are **never** merged.

---

## 10. Result Diversification

- Limits top results to a maximum of 4 songs per artist (relaxed if the user explicitly searched for an artist).
- Limits top results to a maximum of 3 versions of the same track title (interleaving Official, Live, Acoustic, and Remix).

---

## 11. Autocomplete & "Did You Mean?" Engine

- **AutocompleteIndex**: Fast in-memory Trie index initialized from search history, listening history, and seed artist dictionaries.
- **DidYouMeanEngine**: Formats capitalized correction strings (e.g. *"Did you mean: Arijit Singh?"* for query `"arjit"`). Suppressed if the top search result already has an exact match score $\ge 0.75$.

---

## 12. Search Cache & Hierarchy

- **L1 Cache**: In-Memory Prefix Trie suggestions (<50ms).
- **L2 Cache**: Hive Box `aura_search_cache_v2` storing candidate lists keyed by `query|intent|language|region` with LRU eviction (cap: 200 queries) and 24-hour TTL.
- **L3 Cache**: Offline downloads stored in `offline_songs` box.

---

## 13. Quota Management & Rate Limiting

- `ProviderQuota`: Tracks daily usage and resets at midnight.
- `QuotaManager`:
  - YouTube Data API: 10,000 quota units/day (`search.list` costs 100 units).
  - Audius: 10,000 requests/day.
  - Jamendo: 10,000 requests/day.

---

## 14. Circuit Breakers & Provider Health Monitoring

- `ProviderHealth`: Tracks latency, timeout counts, 429 rate limits, and consecutive failure counts.
- **Circuit State Transitions**:
  - `CLOSED`: Normal operation.
  - `OPEN`: 5 consecutive failures trip the circuit. Requests are immediately bypassed for 30 seconds.
  - `HALF_OPEN`: After 30 seconds, 1 test request is sent. If successful, state returns to `CLOSED`.

---

## 15. Database Architecture & Isolation

- **Default Firestore Project**: User accounts, app settings, public playlists.
- **Secondary Isolated Database (`databaseId: 'chat'`)**: Strictly dedicated to ephemeral peer-to-peer messaging and room verification.

---

## 16. Backend Microservice Endpoints

Located in `youtube-extractor-microservice/server.js`:
- `GET /health`: Service health and engine version check.
- `GET /api/search/youtube?q=...&limit=20`: Server-side YouTube Data API v3 proxy with yt-dlp fallback.
- `POST /api/youtube/extract`: Multi-format stream resolution.
- `GET /api/youtube/download?url=...&quality=High`: Direct audio binary stream.

---

## 17. Environment Variables

Template available in `.env.example`:
- `YOUTUBE_API_KEY`: Server-side YouTube Data API v3 key.
- `JAMENDO_CLIENT_ID`: Jamendo client ID.
- `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET`: Spotify credentials.
- `MONGODB_DATA_API_URL` / `MONGODB_API_KEY`: Atlas search endpoints.
- `DEEZER_ENABLED`: `true` / `false`.

---

## 18. Test Architecture & Verification

All automated tests run via `flutter test`:
1. `query_intelligence_test.dart`: Unicode normalization, spell correction, Indic transliteration, intent detection, and entity parsing.
2. `ranking_pipeline_test.dart`: String similarity metrics, exact match boosting, and reaction video penalties.
3. `deduplication_and_diversity_test.dart`: Multi-provider deduplication and anti-clustering diversification.
4. `circuit_breaker_and_quota_test.dart`: Health monitor state transitions and quota cost tracking.
5. `autocomplete_and_cache_test.dart`: Trie prefix queries, did-you-mean evaluations, and cache key serialization.
6. `golden_ranking_cases_test.dart`: Evaluates 103 realistic test cases from `test/fixtures/search_ranking_cases.json`.

---

## 19. Failure & Recovery Behavior

- **Total Network Disconnect**: Pipeline transparently returns matching downloaded songs from local Hive cache with zero error popups.
- **Single Remote Provider Down**: Bounded timeout triggers graceful degradation; other 7 providers fulfill the search query.

---

## 20. Security Model

- **Zero Secret Commits**: All external API keys and database credentials reside strictly in `.env` files or backend environment variables.
- **Chat Database Isolation**: Direct messaging data resides on `databaseId: 'chat'` with field encryption and zero shared access with search indexes.

---

## 21. HUMAN ACTION REQUIRED Document

### A. ZERO-CODE / WEB CONSOLE ACTIONS
1. **Google Cloud Console**:
   - **WHERE**: https://console.cloud.google.com/apis/credentials
   - **WHAT TO CLICK**: Create Credentials → API Key
   - **WHAT TO CREATE**: Restrict to YouTube Data API v3
   - **WHAT VALUE TO ENTER**: "Aura Player YouTube API Key"
   - **WHERE TO COPY**: Place into backend `.env` as `YOUTUBE_API_KEY`
   - **SECRET**: YES
   - **FREQUENCY**: Once

### B. MONGODB ATLAS SEARCH INDEX
1. **MongoDB Atlas Console**:
   - **WHERE**: https://cloud.mongodb.com/ → Search Indexes
   - **WHAT TO CLICK**: Create Search Index → JSON Editor
   - **DATABASE/COLLECTION**: `aura_music.songs`
   - **INDEX NAME**: `search_index`
   - **VALUE**: Paste JSON index definition from README Section 19
   - **FREQUENCY**: Once

### C. RENDER / BACKEND SERVICE SETUP
1. **Render Dashboard**:
   - **WHERE**: https://dashboard.render.com/
   - **WHAT TO CLICK**: New Web Service → Connect `youtube-extractor-microservice`
   - **ENVIRONMENT VARIABLES**: Set `PORT=3000`, `YOUTUBE_API_KEY=<key>`
   - **FREQUENCY**: Once

### D. PHYSICAL ANDROID DEVICE TEST PROCEDURE
1. Install release APK on Android test device.
2. Open app and perform search for `"arjit tum hi ho"` → Confirm *Tum Hi Ho* ranks #1.
3. Search `"तुम ही हो"` (Devanagari) → Confirm Hindi transliteration match.
4. Enable Airplane mode → Confirm offline storage search functions.
5. Import YouTube link → Confirm multi-tier format modal renders (High/Medium/Low).
6. Tap hardware back button on search results → Confirms query is dismissed before switching tabs.
7. Connect USB DAC or Bluetooth Hi-Fi headphones on Android 14+ device → Confirms Bit-Perfect badge displays live sample rate (e.g. 48.0 kHz / 24-bit).

---

## 22. Android 14+ Bit-Perfect Audio Engine & Navigation Architecture

### A. Bit-Perfect Direct HAL Architecture
- Android 14 (API 34) introduced `AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT` to bypass Android OS software mixing, volume scaling, and software sample rate conversion (SRC).
- Implemented via Kotlin MethodChannel `aura_player/bit_perfect` (`MainActivity.kt`) and Dart service `BitPerfectService`.
- Automatically queries available `AudioDeviceInfo` and applies `AudioManager.setPreferredMixerAttributes` with stereo PCM encoding.
- Live sample rate and bit-depth telemetry (e.g. `44.1 kHz`, `48.0 kHz`, `96.0 kHz`, `192.0 kHz / MHz DSD`) is broadcast across Riverpod `audioSpecsProvider` and displayed in `FloatingMiniPlayer` and `FullPlayer`.
- Audiophile modal allows one-tap toggling of Bit-Perfect HAL mode with active DAC hotplug detection.

### B. Device Hardware Back Navigation Stack
- `MainScreen` maintains a persistent navigation tab history stack `_tabHistory`.
- Sequenced back press execution:
  1. If Full Player Sliding Panel is open → Collapses panel.
  2. If Search Tab has active live/submitted query or search results → Clears search and resets pagination.
  3. If nested tab navigator has a pushed sub-route (`Navigator.canPop()`) → Pops sub-route.
  4. If root dialog/modal is open (`navigatorKey.currentState.canPop()`) → Pops modal.
  5. If tab history stack length > 1 → Pops to previous tab in user's navigation journey.
  6. If on root Home tab → Prompts with double-tap confirmation toast before exiting application.
