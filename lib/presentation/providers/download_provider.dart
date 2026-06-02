import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/download_service.dart';
import '../../domain/entities/song.dart';

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final dio = Dio();
  return DownloadService(dio: dio);
});

final downloadProgressProvider = StateProvider<Map<String, double>>((ref) {
  return {};
});

final downloadSongProvider =
    StateNotifierProvider<DownloadNotifier, AsyncValue<void>>((ref) {
  return DownloadNotifier(ref.watch(downloadServiceProvider), ref);
});

class DownloadNotifier extends StateNotifier<AsyncValue<void>> {
  final DownloadService _service;
  final Ref _ref;

  DownloadNotifier(this._service, this._ref) : super(const AsyncValue.data(null));

  Future<void> downloadSong(Song song) async {
    state = const AsyncValue.loading();
    try {
      await _service.downloadSong(
        song,
        onProgress: (received, total) {
          final progress = received / total;
          _ref.read(downloadProgressProvider.notifier).state = {
            ...?_ref.read(downloadProgressProvider),
            song.id: progress,
          };
        },
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteSong(Song song) async {
    try {
      await _service.deleteSongDownload(song);
    } catch (e) {
      print('Delete error: $e');
    }
  }
}

final isSongDownloadedProvider =
    FutureProvider.family<bool, Song>((ref, song) async {
  final service = ref.watch(downloadServiceProvider);
  return service.isSongDownloaded(song);
});
