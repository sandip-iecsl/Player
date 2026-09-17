import '../models/search_models.dart';

/// Quota policy and counters for an individual provider
class ProviderQuota {
  final SearchProviderType provider;
  final int dailyLimit;
  final int requestCost;
  int usedToday;
  DateTime lastResetDate;
  bool isQuotaExceeded;

  ProviderQuota({
    required this.provider,
    required this.dailyLimit,
    this.requestCost = 1,
    this.usedToday = 0,
    DateTime? lastResetDate,
    this.isQuotaExceeded = false,
  }) : lastResetDate = lastResetDate ?? DateTime.now();

  int get remainingEstimate => (dailyLimit - usedToday).clamp(0, dailyLimit);

  bool canMakeRequest() {
    _checkDailyReset();
    return !isQuotaExceeded && (usedToday + requestCost <= dailyLimit);
  }

  void recordRequest() {
    _checkDailyReset();
    usedToday += requestCost;
    if (usedToday >= dailyLimit) {
      isQuotaExceeded = true;
    }
  }

  void _checkDailyReset() {
    final now = DateTime.now();
    if (now.day != lastResetDate.day || now.month != lastResetDate.month || now.year != lastResetDate.year) {
      usedToday = 0;
      isQuotaExceeded = false;
      lastResetDate = now;
    }
  }

  Map<String, dynamic> toMap() => {
    'provider': provider.name,
    'dailyLimit': dailyLimit,
    'usedToday': usedToday,
    'remainingEstimate': remainingEstimate,
    'isQuotaExceeded': isQuotaExceeded,
    'lastResetDate': lastResetDate.toIso8601String(),
  };
}
