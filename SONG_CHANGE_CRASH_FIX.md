# Song Change Crash Fix - Implementation Plan

## Problem Analysis

The app crashes unexpectedly when changing songs due to several critical issues:

### Root Causes Identified

1. **Race Conditions in _playSong**
   - Multiple concurrent calls to `_playSong` can occur when rapidly skipping tracks
   - Mutex (`_isPlayingSong`) has a timeout that can be exceeded
   - Session ID checking is insufficient to prevent all race conditions

2. **Array Index Out of Bounds**
   - `skipToNext()`/`skipToPrevious()` don't validate `_currentIndex` before accessing `_queue[_currentIndex]`
   - Queue can be modified while song is loading
   - `_onTrackEnded()` can increment `_currentIndex` beyond queue length

3. **Null Pointer Exceptions**
   - Missing null checks when accessing queue elements
   - `_currentSong` can be null during rapid transitions
   - Album art and metadata access without validation

4. **AudioPlayer State Issues**
   - `stop()` is called but `await` is not always honored
   - Brief 80ms delay insufficient for ExoPlayer cleanup
   - Player can be in invalid state when setting new source

5. **Session Management**
   - `_playSessionId` increments too quickly during rapid skips
   - Old sessions can still execute after being cancelled
   - Missing guards in critical sections

## Proposed Fixes

### 1. Enhanced Index Validation

```dart
// Add safe queue access helper
Song? _getSafeQueueSong(int index) {
  if (_queue.isEmpty || index < 0 || index >= _queue.length) {
    print('[Audio] ⚠️ Invalid queue access: index=$index, length=${_queue.length}');
    return null;
  }
  return _queue[index];
}
```

### 2. Improved skipToNext/skipToPrevious

```dart
@override
Future<void> skipToNext() async {
  try {
    print('[Audio] ⏭️ Skip to next requested');
    
    // Validate queue state
    if (_queue.isEmpty) {
      print('[Audio] ⚠️ Cannot skip: queue is empty');
      return;
    }

    // Cancel any ongoing skip operations
    _skipDebounceTimer?.cancel();
    _skipDebounceTimer = Timer(const Duration(milliseconds: 300), () {});

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      final nextSong = _getSafeQueueSong(_currentIndex);
      if (nextSong != null) {
        _currentSongController.add(nextSong);
        await _playSong(nextSong);
      } else {
        print('[Audio] ⚠️ Skip failed: next song is null');
      }
    } else if (_repeatMode == AudioServiceRepeatMode.all) {
      _currentIndex = 0;
      final firstSong = _getSafeQueueSong(_currentIndex);
      if (firstSong != null) {
        _currentSongController.add(firstSong);
        await _playSong(firstSong);
      }
    } else {
      _playNextAlgorithmSong();
    }
  } catch (e, stackTrace) {
    print('[Audio] ❌ Skip next error: $e');
    print('[Audio] Stack trace: $stackTrace');
    // Don't crash - try to recover
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      final currentSong = _getSafeQueueSong(_currentIndex);
      if (currentSong != null) {
        _currentSongController.add(currentSong);
      }
    }
  }
}
```

### 3. Enhanced _playSong Mutex

```dart
Future<void> _playSong(Song song) async {
  final int currentSession = ++_playSessionId;
  
  // Enhanced mutex with timeout and forced release
  int waitCount = 0;
  const maxWait = 50; // Increased from 40
  while (_isPlayingSong && waitCount < maxWait) {
    await Future.delayed(const Duration(milliseconds: 25));
    waitCount++;
    if (_playSessionId != currentSession) {
      print('[Audio] ℹ️ Play session cancelled while waiting for mutex');
      return;
    }
  }
  
  // Force release if timeout exceeded
  if (_isPlayingSong && waitCount >= maxWait) {
    print('[Audio] ⚠️ Mutex timeout exceeded, forcing release');
    _isPlayingSong = false;
  }
  
  if (_playSessionId != currentSession) return;
  
  _isPlayingSong = true;
  _hasFiredCompletion = false;
  
  try {
    // Validate song before processing
    if (song.id.isEmpty) {
      throw Exception('Invalid song: empty ID');
    }
    
    print('[Audio] 🎵 ── Loading: "${song.title}" by ${song.artist} ──');
    
    // ... rest of implementation with added try-catch blocks
  } catch (e, stackTrace) {
    print('[Audio] ❌ Critical error in _playSong: $e');
    print('[Audio] Stack trace: $stackTrace');
    _consecutiveFailures++;
    
    // Enhanced error recovery
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      _consecutiveFailures = 0;
      await stop();
    } else {
      // Try next song with validation
      if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
        final nextSong = _getSafeQueueSong(_currentIndex);
        if (nextSong != null) {
          _currentSongController.add(nextSong);
          _isPlayingSong = false; // Release mutex before recursive call
          await _playSong(nextSong);
          return;
        }
      }
      await stop();
    }
  } finally {
    _isPlayingSong = false;
  }
}
```

### 4. Improved AudioPlayer Cleanup

```dart
// Enhanced stop with better cleanup
print('[Audio] ⏹ Stopping previous player instance before new source...');
try {
  // Stop with timeout to prevent hanging
  await _audioPlayer.stop().timeout(
    const Duration(milliseconds: 500),
    onTimeout: () {
      print('[Audio] ⚠️ Stop timeout, forcing player reset');
    },
  );
  
  // Increased delay for reliable ExoPlayer cleanup
  await Future.delayed(const Duration(milliseconds: 150));
} catch (e) {
  print('[Audio] ⚠️ Stop error (continuing): $e');
}

// Verify session hasn't changed during cleanup
if (_playSessionId != currentSession) {
  print('[Audio] ℹ️ Session changed during cleanup, aborting');
  return;
}
```

### 5. Enhanced _onTrackEnded Validation

```dart
void _onTrackEnded() {
  print('[Audio] 🏁 Track ended - Current index: $_currentIndex, Queue length: ${_queue.length}');
  
  // Validate queue state
  if (_queue.isEmpty) {
    print('[Audio] ⚠️ Track ended but queue is empty');
    _audioPlayer.stop();
    return;
  }
  
  // Step 1: Repeat One
  if (_repeatMode == AudioServiceRepeatMode.one) {
    print('[Audio] 🔁 Repeat ONE - Replaying current track');
    seek(Duration.zero);
    play();
    return;
  }

  // Step 2: Check boundaries with validation
  if (_currentIndex < _queue.length - 1) {
    print('[Audio] ➡️ Moving to next song in queue');
    _currentIndex++;
    final nextSong = _getSafeQueueSong(_currentIndex);
    if (nextSong != null) {
      _currentSongController.add(nextSong);
      _playSong(nextSong);
    } else {
      print('[Audio] ⚠️ Next song is null, stopping');
      _audioPlayer.stop();
    }
    return;
  }

  // ... rest of implementation
}
```

### 6. Debounce Skip Operations

```dart
// Add at class level
Timer? _skipDebounceTimer;
static const _skipDebounceDuration = Duration(milliseconds: 300);

// In skipToNext
_skipDebounceTimer?.cancel();
_skipDebounceTimer = Timer(_skipDebounceDuration, () {
  // Actual skip logic here
});
```

## Implementation Steps

1. ✅ Add `_getSafeQueueSong()` helper method
2. ✅ Update `skipToNext()` with validation and debouncing
3. ✅ Update `skipToPrevious()` with validation and debouncing
4. ✅ Enhance `_playSong()` mutex and error handling
5. ✅ Improve AudioPlayer cleanup with timeout
6. ✅ Add validation to `_onTrackEnded()`
7. ✅ Add comprehensive error logging with stack traces
8. ✅ Test rapid song changes
9. ✅ Test queue modifications during playback
10. ✅ Test error recovery scenarios

## Testing Checklist

- [ ] Rapidly tap next/previous buttons (10+ times quickly)
- [ ] Change songs while current song is still loading
- [ ] Skip through entire queue quickly
- [ ] Test with empty queue scenarios
- [ ] Test with single-song queue
- [ ] Test repeat modes (one, all, off)
- [ ] Test shuffle mode on/off
- [ ] Test network interruptions during song change
- [ ] Test app backgrounding during song change
- [ ] Monitor logs for any unhandled exceptions

## Expected Improvements

1. **Zero crashes** during rapid song changes
2. **Graceful degradation** when errors occur
3. **Better error messages** for debugging
4. **Improved user experience** with smoother transitions
5. **Enhanced stability** during edge cases

## Files to Modify

- `lib/data/services/audio_service.dart`

## Verification

Run `flutter analyze` and `flutter test` after implementation.
Monitor crash reports and logs for 24-48 hours after deployment.
