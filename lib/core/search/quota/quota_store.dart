import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/search_models.dart';
import 'provider_quota.dart';

/// Storage backend for persistent daily quota tracking
class QuotaStore {
  static const String boxName = 'aura_quota_box';

  Box? get _box {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return null;
  }

  Future<void> saveQuota(ProviderQuota quota) async {
    final box = _box;
    if (box != null) {
      await box.put(quota.provider.name, jsonEncode(quota.toMap()));
    }
  }

  ProviderQuota? loadQuota(SearchProviderType provider, int defaultDailyLimit, {int cost = 1}) {
    final box = _box;
    if (box != null && box.containsKey(provider.name)) {
      try {
        final raw = box.get(provider.name);
        final Map<String, dynamic> map = raw is String ? jsonDecode(raw) : Map<String, dynamic>.from(raw as Map);
        return ProviderQuota(
          provider: provider,
          dailyLimit: map['dailyLimit'] as int? ?? defaultDailyLimit,
          requestCost: cost,
          usedToday: map['usedToday'] as int? ?? 0,
          lastResetDate: map['lastResetDate'] != null ? DateTime.tryParse(map['lastResetDate']) : DateTime.now(),
          isQuotaExceeded: map['isQuotaExceeded'] == true,
        );
      } catch (_) {}
    }
    return ProviderQuota(
      provider: provider,
      dailyLimit: defaultDailyLimit,
      requestCost: cost,
    );
  }
}
