import 'package:flutter/foundation.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kGuestTier = 'guest';
const kFreeTier = 'free';
const kPremiumTier = 'premium';

class TierLimits {
  const TierLimits({
    required this.tier,
    required this.maxLiveRooms,
    required this.maxMembers,
    required this.maxSessionMinutes,
    required this.maxTotalSessionMinutes,
    required this.avLevel,
    required this.persistentRoomCap,
    required this.dormantHours,
    required this.freeExtensionMinutes,
  });

  static const fallback = TierLimits(
    tier: kFreeTier,
    maxLiveRooms: 4,
    maxMembers: 8,
    maxSessionMinutes: 240,
    maxTotalSessionMinutes: 240,
    avLevel: .voice,
    persistentRoomCap: 0,
    dormantHours: 24,
    freeExtensionMinutes: 60,
  );

  final String tier;
  final int maxLiveRooms;
  final int maxMembers;
  final int maxSessionMinutes;
  final int maxTotalSessionMinutes;
  final AvLevel avLevel;
  final int persistentRoomCap;
  final int dormantHours;
  final int freeExtensionMinutes;

  bool get isPremium => tier == kPremiumTier;
  bool get isGuest => tier == kGuestTier;

  bool get picksExtensionLength => maxTotalSessionMinutes > maxSessionMinutes;

  bool get hasFreeExtension => !picksExtensionLength && freeExtensionMinutes > 0;

  factory TierLimits.fromJson(Map<String, dynamic> json) => TierLimits(
    tier: json['tier'] as String,
    maxLiveRooms: (json['max_live_rooms'] as num).toInt(),
    maxMembers: (json['max_members'] as num).toInt(),
    maxSessionMinutes: (json['max_session_minutes'] as num).toInt(),
    maxTotalSessionMinutes: (json['max_total_session_minutes'] as num).toInt(),
    avLevel: AvLevel.fromWire(json['av_level'] as String?),
    persistentRoomCap: (json['persistent_room_cap'] as num?)?.toInt() ?? 0,
    dormantHours: (json['dormant_hours'] as num?)?.toInt() ?? 0,
    freeExtensionMinutes: (json['free_extension_minutes'] as num?)?.toInt() ?? 0,
  );
}

bool tierWearsCrown(String? tier) => tier == kPremiumTier;

Set<String> premiumMembersFrom(Map<String, String> tiers) => {
  for (final entry in tiers.entries)
    if (tierWearsCrown(entry.value)) entry.key,
};

class EntitlementService extends ChangeNotifier {
  EntitlementService._();
  static final instance = EntitlementService._();

  SupabaseClient get _client => Supabase.instance.client;

  TierLimits? _limits;

  TierLimits? get limits => _limits;

  TierLimits get limitsOrFallback => _limits ?? TierLimits.fallback;

  String get tier => _limits?.tier ?? kFreeTier;
  bool get isPremium => _limits?.isPremium ?? false;

  Future<TierLimits?> load() async {
    if (_client.auth.currentUser == null) {
      clear();
      return null;
    }
    try {
      final row = await _client.rpc('my_entitlement');
      if (row == null) return _limits;
      final map = row is List
          ? (row.first as Map).cast<String, dynamic>()
          : (row as Map).cast<String, dynamic>();
      _limits = TierLimits.fromJson(map);
      notifyListeners();
      return _limits;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the caller entitlement');
      return _limits;
    }
  }

  void clear() {
    if (_limits == null) return;
    _limits = null;
    notifyListeners();
  }
}
