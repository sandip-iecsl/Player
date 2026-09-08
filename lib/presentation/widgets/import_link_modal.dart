import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/youtube_audio_format.dart';
import '../../data/services/audio_service.dart';
import '../../data/services/offline_storage_service.dart';
import '../../data/services/quality_settings_service.dart';
import '../../data/services/youtube_extractor_service.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import '../providers/theme_provider.dart';

class ImportLinkModal extends ConsumerStatefulWidget {
  const ImportLinkModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ImportLinkModal(),
    );
  }

  @override
  ConsumerState<ImportLinkModal> createState() => _ImportLinkModalState();
}

class _ImportLinkModalState extends ConsumerState<ImportLinkModal> {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final YouTubeExtractorService _extractor = YouTubeExtractorService();

  bool _isExtracting = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  Song? _extractedSong;
  List<YouTubeAudioFormat> _availableFormats = [];
  YouTubeAudioFormat? _selectedFormat;
  String _preferredQuality = 'High';

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _checkClipboard();
  }

  Future<void> _loadUserPreferences() async {
    final quality = await QualitySettingsService.getPreferredDownloadQuality();
    if (mounted) {
      setState(() {
        _preferredQuality = quality;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim() ?? '';
      if (text.isNotEmpty && YouTubeExtractorService.isYouTubeUrl(text)) {
        setState(() {
          _urlController.text = text;
        });
        _extractLink(text);
      }
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim() ?? '';
      if (text.isEmpty) {
        setState(() => _errorMessage = 'Clipboard is empty');
        return;
      }
      setState(() {
        _urlController.text = text;
        _errorMessage = null;
      });
      _extractLink(text);
    } catch (e) {
      setState(() => _errorMessage = 'Could not read clipboard');
    }
  }

  Future<void> _extractLink(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    if (!YouTubeExtractorService.isYouTubeUrl(trimmed)) {
      setState(() {
        _errorMessage = 'Please enter a valid YouTube, YouTube Music, or youtu.be link';
        _extractedSong = null;
        _availableFormats = [];
        _selectedFormat = null;
      });
      return;
    }

    if (_isExtracting) return;

    setState(() {
      _isExtracting = true;
      _errorMessage = null;
      _extractedSong = null;
      _availableFormats = [];
      _selectedFormat = null;
    });

    try {
      final result = await _extractor.extractTrackWithFormats(trimmed);
      if (mounted) {
        if (result != null) {
          // Select format according to saved preference
          final matchingFormat = result.availableFormats.firstWhere(
            (f) => f.quality == _preferredQuality,
            orElse: () => result.selectedFormat,
          );

          setState(() {
            _extractedSong = result.song;
            _availableFormats = result.availableFormats;
            _selectedFormat = matchingFormat;
            _isExtracting = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Could not extract audio stream from this link. Make sure the microservice is active.';
            _isExtracting = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Extraction error: $e';
          _isExtracting = false;
        });
      }
    }
  }

  void _onSelectQuality(YouTubeAudioFormat format) {
    setState(() {
      _selectedFormat = format;
      _preferredQuality = format.quality;
    });
    // Persist to user settings box
    QualitySettingsService.setPreferredDownloadQuality(format.quality);
  }

  Future<void> _playNow() async {
    if (_extractedSong == null) return;
    var song = _extractedSong!;
    if (_selectedFormat != null && _selectedFormat!.streamUrl.isNotEmpty) {
      song = song.copyWith(
        previewUrl: _selectedFormat!.streamUrl,
        bitrate: _selectedFormat!.bitrate,
        formatId: _selectedFormat!.formatId,
      );
    }

    Navigator.of(context, rootNavigator: true).pop();

    try {
      debugPrint('[ImportLinkModal] 🎵 Playing imported track: ${song.title} (${_selectedFormat?.bitrate ?? "default"})');
      await ref.read(audioServiceProvider).loadQueue([song], context: PlaybackContext.search);
    } catch (e) {
      debugPrint('[ImportLinkModal] ❌ Playback error: $e');
    }
  }

  Future<void> _downloadTrack() async {
    if (_extractedSong == null) return;
    var song = _extractedSong!;
    if (_selectedFormat != null) {
      song = song.copyWith(
        bitrate: _selectedFormat!.bitrate,
        formatId: _selectedFormat!.formatId,
      );
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      await OfflineStorageService.downloadSong(
        song,
        (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
        selectedFormat: _selectedFormat,
        formatId: _selectedFormat?.formatId,
        bitrate: _selectedFormat?.bitrate,
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Downloaded "${song.title}" (${_selectedFormat?.bitrate ?? "HQ"}) for offline playback!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1E26),
            behavior: SnackBarBehavior.floating,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withAlpha(35)),
            ),
            margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download failed: $e';
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = mediaQuery.padding.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withAlpha(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(150),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
      child: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.link_rounded, color: Colors.redAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paste Link to Play & Download',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'YouTube & YouTube Music with Bitrate Selection',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Input field + Paste button
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F26),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(25)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search, color: Colors.white38, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        focusNode: _focusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Paste YouTube / YouTube Music URL...',
                          hintStyle: TextStyle(color: Colors.white.withAlpha(90), fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: (val) => _extractLink(val),
                      ),
                    ),
                    if (_urlController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                        onPressed: () {
                          _urlController.clear();
                          setState(() {
                            _extractedSong = null;
                            _errorMessage = null;
                            _availableFormats = [];
                            _selectedFormat = null;
                          });
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withAlpha(20),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.paste_rounded, size: 15, color: Colors.white70),
                        label: const Text(
                          'Paste',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        onPressed: _pasteFromClipboard,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Loading indicator
              if (_isExtracting)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.redAccent),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Resolving multi-format audio streams & bitrates...',
                        style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13),
                      ),
                    ],
                  ),
                ),

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withAlpha(70)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Extracted song preview card
              if (_extractedSong != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E26),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 60,
                          height: 60,
                          color: Colors.black26,
                          child: _extractedSong!.albumArt != null
                              ? Image.network(
                                  _extractedSong!.albumArt!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white38),
                                )
                              : const Icon(Icons.music_note, color: Colors.white38),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Metadata
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _extractedSong!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _extractedSong!.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, color: Colors.white38, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDuration(_extractedSong!.duration),
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                if (_selectedFormat != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withAlpha(35),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _selectedFormat!.bitrate,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // MODULE 2: Audio Resolution / Bitrate Quality Selector Card
                if (_availableFormats.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SELECT AUDIO RESOLUTION / BITRATE',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: _availableFormats.map((format) {
                      final isSelected = _selectedFormat?.formatId == format.formatId ||
                          _selectedFormat?.quality == format.quality;

                      String subtitleText;
                      IconData qualityIcon;
                      Color tierAccentColor;

                      if (format.isHighQuality) {
                        subtitleText = 'Best audio fidelity (${format.estimatedSizeMb}/song)';
                        qualityIcon = Icons.high_quality_rounded;
                        tierAccentColor = const Color(0xFF00E676);
                      } else if (format.isMediumQuality) {
                        subtitleText = 'Balanced quality & storage (${format.estimatedSizeMb}/song)';
                        qualityIcon = Icons.graphic_eq_rounded;
                        tierAccentColor = const Color(0xFF00B0FF);
                      } else {
                        subtitleText = 'Minimal size & fast download (${format.estimatedSizeMb}/song)';
                        qualityIcon = Icons.data_saver_on_rounded;
                        tierAccentColor = const Color(0xFFFF9100);
                      }

                      return InkWell(
                        onTap: () => _onSelectQuality(format),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? tierAccentColor.withAlpha(25) : const Color(0xFF1E1E26),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? tierAccentColor.withAlpha(180) : Colors.white.withAlpha(20),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                qualityIcon,
                                color: isSelected ? tierAccentColor : Colors.white54,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '${format.bitrate} (${format.quality})',
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : Colors.white70,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (isSelected) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: tierAccentColor.withAlpha(50),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'DEFAULT',
                                              style: TextStyle(
                                                color: tierAccentColor,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitleText,
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(120),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? tierAccentColor : Colors.white38,
                                    width: 2,
                                  ),
                                  color: isSelected ? tierAccentColor : Colors.transparent,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, size: 14, color: Colors.black)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],

                // Action buttons: Play Now and Download
                Row(
                  children: [
                    // Play Now button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withAlpha(20),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text(
                          'Play Now',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: _playNow,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Download button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                          shadowColor: Colors.redAccent.withAlpha(100),
                        ),
                        icon: _isDownloading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: _downloadProgress > 0 ? _downloadProgress : null,
                                  strokeWidth: 2,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          _isDownloading
                              ? '${(_downloadProgress * 100).toStringAsFixed(0)}%'
                              : 'Download',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: _isDownloading ? null : _downloadTrack,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
