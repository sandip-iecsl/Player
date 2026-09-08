import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../domain/entities/lyrics_data.dart';
import '../../core/constants/app_colors.dart';

class SynchronizedLyricsWidget extends StatefulWidget {
  final LyricsData lyricsData;
  final Stream<Duration> positionStream;

  const SynchronizedLyricsWidget({
    super.key,
    required this.lyricsData,
    required this.positionStream,
  });

  @override
  State<SynchronizedLyricsWidget> createState() => _SynchronizedLyricsWidgetState();
}

class _SynchronizedLyricsWidgetState extends State<SynchronizedLyricsWidget> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  
  int _currentIndex = 0;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _listenToPosition();
  }

  void _listenToPosition() {
    widget.positionStream.listen((position) {
      if (!mounted || widget.lyricsData.lines == null) return;
      
      final lines = widget.lyricsData.lines!;
      int newIndex = 0;

      for (int i = 0; i < lines.length; i++) {
        if (position >= lines[i].timestamp) {
          newIndex = i;
        } else {
          break;
        }
      }

      if (newIndex != _currentIndex) {
        setState(() {
          _currentIndex = newIndex;
        });
        
        if (!_isUserScrolling && _itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: _currentIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.3, // Scroll so the active line is slightly above the middle
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.lyricsData.isSynced) {
      return SingleChildScrollView(
        child: Text(
          widget.lyricsData.plainLyrics ?? 'No lyrics available.',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            height: 1.6,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final lines = widget.lyricsData.lines!;

    return GestureDetector(
      onPanDown: (_) => _isUserScrolling = true,
      onPanCancel: () => _isUserScrolling = false,
      onPanEnd: (_) {
        // Resume auto-scroll after 3 seconds of inactivity
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _isUserScrolling = false;
          }
        });
      },
      child: ScrollablePositionedList.builder(
        itemCount: lines.length,
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        padding: const EdgeInsets.symmetric(vertical: 60),
        itemBuilder: (context, index) {
          final line = lines[index];
          final isActive = index == _currentIndex;
          final isPast = index < _currentIndex;
          
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Text(
              line.text,
              style: TextStyle(
                color: isActive 
                    ? AppColors.neonPink // Central Style Dynamic Accent
                    : (isPast ? AppColors.textSecondary.withOpacity(0.5) : AppColors.textPrimary),
                fontSize: isActive ? 24 : 18,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }
}
