import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/profile_models.dart';

bool shouldShowPremiumChip({required bool isPremium}) {
  return !isPremium;
}

bool shouldShowQuotaChip({required Profile? profile}) {
  return profile != null && !profile.isGuest;
}

void main() {
  group('Lobby Go Premium chip visibility', () {
    test('visible for signed-in free user', () {
      expect(shouldShowPremiumChip(isPremium: false), isTrue);
    });

    test('visible for guest user', () {
      expect(shouldShowPremiumChip(isPremium: false), isTrue);
    });

    test('hidden for premium user', () {
      expect(shouldShowPremiumChip(isPremium: true), isFalse);
    });
  });

  group('Lobby Quota chip visibility', () {
    const freeProfile = Profile(id: 'u1', displayName: 'Sam', isGuest: false);
    const guestProfile = Profile(id: 'u2', displayName: 'Guest-1234', isGuest: true);

    test('visible for signed-in free user', () {
      expect(shouldShowQuotaChip(profile: freeProfile), isTrue);
    });

    test('hidden for guest user', () {
      expect(shouldShowQuotaChip(profile: guestProfile), isFalse);
    });

    test('hidden when profile is null', () {
      expect(shouldShowQuotaChip(profile: null), isFalse);
    });
  });

  group('Lobby Pre-upload subtitle formatting', () {
    String formatPreUploadSubtitle({
      required bool isPremium,
      required bool isGuest,
      required int remainingBytes,
    }) {
      return isPremium
          ? 'Unlimited uploads with Premium • Up to 10 GB'
          : isGuest
          ? 'Sign in for free 2.5 GB streaming'
          : '${Profile.formatBytes(remainingBytes)} weekly quota available • Up to 2 GB';
    }

    test('guest subtitle promotes signing in and premium', () {
      final sub = formatPreUploadSubtitle(isPremium: false, isGuest: true, remainingBytes: 0);
      expect(sub, equals('Sign in for free 2.5 GB streaming'));
    });

    test('free user subtitle shows available weekly quota', () {
      final sub = formatPreUploadSubtitle(
        isPremium: false,
        isGuest: false,
        remainingBytes: 2 * 1024 * 1024 * 1024,
      );
      expect(sub, contains('2.0 GB weekly quota available'));
    });

    test('premium subtitle indicates unlimited uploads', () {
      final sub = formatPreUploadSubtitle(isPremium: true, isGuest: false, remainingBytes: 0);
      expect(sub, equals('Unlimited uploads with Premium • Up to 10 GB'));
    });
  });
}
