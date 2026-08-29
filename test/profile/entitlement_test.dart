import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/profile/entitlement_service.dart';

void main() {
  group('TierLimits Media Sharing', () {
    test('parses media sharing fields from json', () {
      final freeLimits = TierLimits.fromJson({
        'tier': 'free',
        'max_live_rooms': 4,
        'max_members': 8,
        'max_session_minutes': 240,
        'max_total_session_minutes': 240,
        'av_level': 'voice',
        'persistent_room_cap': 0,
        'dormant_hours': 24,
        'free_extension_minutes': 60,
        'media_sharing': 'limited',
        'media_sharing_weekly_bytes': 2684354560,
      });

      expect(freeLimits.mediaSharing, 'limited');
      expect(freeLimits.mediaSharingWeeklyBytes, 2684354560);
      expect(freeLimits.mediaSharingMaxSizeBytes, 2147483648);
      expect(freeLimits.canShareMedia, isTrue);
      expect(freeLimits.hasUnlimitedSharing, isFalse);

      final premiumLimits = TierLimits.fromJson({
        'tier': 'premium',
        'max_live_rooms': 20,
        'max_members': 16,
        'max_session_minutes': 240,
        'max_total_session_minutes': 1440,
        'av_level': 'video',
        'persistent_room_cap': 20,
        'dormant_hours': 24,
        'free_extension_minutes': 0,
        'media_sharing': 'full',
        'media_sharing_weekly_bytes': 0,
      });

      expect(premiumLimits.mediaSharing, 'full');
      expect(premiumLimits.mediaSharingWeeklyBytes, 0);
      expect(premiumLimits.mediaSharingMaxSizeBytes, 10737418240);
      expect(premiumLimits.canShareMedia, isTrue);
      expect(premiumLimits.hasUnlimitedSharing, isTrue);

      final guestLimits = TierLimits.fromJson({
        'tier': 'guest',
        'max_live_rooms': 1,
        'max_members': 4,
        'max_session_minutes': 60,
        'max_total_session_minutes': 60,
        'av_level': 'none',
        'persistent_room_cap': 0,
        'dormant_hours': 0,
        'free_extension_minutes': 0,
        'media_sharing': 'none',
        'media_sharing_weekly_bytes': 0,
      });

      expect(guestLimits.mediaSharing, 'none');
      expect(guestLimits.mediaSharingWeeklyBytes, 0);
      expect(guestLimits.canShareMedia, isFalse);
      expect(guestLimits.hasUnlimitedSharing, isFalse);
    });

    test('fallback limits allow limited sharing', () {
      expect(TierLimits.fallback.canShareMedia, isTrue);
      expect(TierLimits.fallback.mediaSharing, 'limited');
      expect(TierLimits.fallback.mediaSharingWeeklyBytes, 2684354560);
      expect(TierLimits.fallback.mediaSharingMaxSizeBytes, 2147483648);
    });
  });
}
