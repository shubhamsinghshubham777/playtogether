import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/profile/profile_models.dart';

bool shouldShowPremiumChip({required Profile? profile, required bool isPremium}) {
  return profile != null && !profile.isGuest && !isPremium;
}

void main() {
  group('Lobby Go Premium chip visibility', () {
    const freeProfile = Profile(id: 'u1', displayName: 'Sam', isGuest: false);
    const guestProfile = Profile(id: 'u2', displayName: 'Guest-1234', isGuest: true);

    test('visible for signed-in free user', () {
      expect(shouldShowPremiumChip(profile: freeProfile, isPremium: false), isTrue);
    });

    test('hidden for guest user', () {
      expect(shouldShowPremiumChip(profile: guestProfile, isPremium: false), isFalse);
    });

    test('hidden for premium user', () {
      expect(shouldShowPremiumChip(profile: freeProfile, isPremium: true), isFalse);
    });

    test('hidden when profile is null', () {
      expect(shouldShowPremiumChip(profile: null, isPremium: false), isFalse);
    });
  });
}
