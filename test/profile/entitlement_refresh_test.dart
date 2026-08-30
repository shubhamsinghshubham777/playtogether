import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/rooms/room_models.dart';

void main() {
  group('EntitlementService', () {
    test('defaults to free tier when limits not loaded', () {
      expect(EntitlementService.instance.tier, kFreeTier);
      expect(EntitlementService.instance.isPremium, isFalse);
      expect(EntitlementService.instance.limitsOrFallback.maxSessionMinutes, 240);
    });

    test('clear resets limits and notifies', () {
      var notified = 0;
      EntitlementService.instance.addListener(() => notified++);
      EntitlementService.instance.clear();
      expect(EntitlementService.instance.limits, isNull);
    });

    test('tier helpers evaluate premium status accurately', () {
      expect(tierWearsCrown(kPremiumTier), isTrue);
      expect(tierWearsCrown(kFreeTier), isFalse);
      expect(tierWearsCrown(kGuestTier), isFalse);
      expect(tierWearsCrown(null), isFalse);

      final members = premiumMembersFrom({
        'user_1': kPremiumTier,
        'user_2': kFreeTier,
        'user_3': kGuestTier,
      });
      expect(members, {'user_1'});
    });

    test('TierLimits parses JSON correctly and sets properties', () {
      final json = {
        'tier': 'premium',
        'max_live_rooms': 20,
        'max_members': 16,
        'max_session_minutes': 720,
        'max_total_session_minutes': 720,
        'av_level': 'video',
        'persistent_room_cap': 20,
        'dormant_hours': 720,
        'free_extension_minutes': 0,
      };

      final limits = TierLimits.fromJson(json);
      expect(limits.tier, kPremiumTier);
      expect(limits.isPremium, isTrue);
      expect(limits.isGuest, isFalse);
      expect(limits.maxLiveRooms, 20);
      expect(limits.maxMembers, 16);
      expect(limits.avLevel, AvLevel.video);
      expect(limits.persistentRoomCap, 20);
    });
  });
}
