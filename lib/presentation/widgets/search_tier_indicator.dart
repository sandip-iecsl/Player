import 'package:flutter/material.dart';
import '../../core/search/search_tier.dart';
import '../providers/search_failover_provider.dart';

/// A sleek, modern glassmorphic chip indicating the active search tier and fallback status.
/// Highlights Tier 3 (Offline Fail-Safe) with a subtle warning so users know they are viewing local results.
class SearchTierIndicator extends StatelessWidget {
  final SearchFailoverState state;
  final VoidCallback? onRetryOnline;

  const SearchTierIndicator({
    super.key,
    required this.state,
    this.onRetryOnline,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isIdle || (state.results.isEmpty && !state.isLoading)) {
      return const SizedBox.shrink();
    }

    final tier = state.resolvedTier;
    if (tier == null && !state.isLoading) return const SizedBox.shrink();

    if (state.isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purpleAccent.shade100),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Searching Multi-Tier Network...',
              style: TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Colors and icons based on Tier
    Color tierColor;
    IconData tierIcon;
    String tierBadgeText;

    switch (tier!) {
      case SearchTier.cache:
        tierColor = const Color(0xFF00E676); // Emerald Green
        tierIcon = Icons.bolt_rounded;
        tierBadgeText = '⚡ 0ms Instant Cache (0 Cost)';
        break;
      case SearchTier.tier1MongoAtlas:
        tierColor = const Color(0xFF00B0FF); // Electric Cyan
        tierIcon = Icons.cloud_done_rounded;
        tierBadgeText = 'MongoDB Atlas (Primary M0)';
        break;
      case SearchTier.tier2Algolia:
        tierColor = const Color(0xFFFF9100); // Amber
        tierIcon = Icons.speed_rounded;
        tierBadgeText = 'Algolia (Tier 2 Cloud Fallback)';
        break;
      case SearchTier.tier3LocalFailsafe:
        tierColor = const Color(0xFFFF5252); // Coral / Warning
        tierIcon = Icons.offline_bolt_rounded;
        tierBadgeText = 'Tier 3: Local Offline Fail-Safe (0 Cloud Reads)';
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Subtle badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: tierColor.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: tierColor.withAlpha(90), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tierIcon, size: 14, color: tierColor),
              const SizedBox(width: 6),
              Text(
                tierBadgeText,
                style: TextStyle(
                  color: tierColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              if (state.latency != null && state.latency! > Duration.zero) ...[
                const SizedBox(width: 6),
                Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: tierColor.withAlpha(130),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${state.latency!.inMilliseconds}ms',
                  style: TextStyle(
                    color: tierColor.withAlpha(200),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),

        // If Tier 3 Local Fail-Safe is active, show informative banner for the user
        if (state.isOfflineFallback)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF261818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x4DFF5252)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: Colors.orangeAccent, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline / Local Search Active',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cloud providers are unreachable or rate-limited. Serving local library results.',
                        style: TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRetryOnline != null)
                  TextButton(
                    onPressed: onRetryOnline,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Retry Cloud',
                      style: TextStyle(
                        color: Color(0xFF00B0FF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
