import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/profile_models.dart';

void main() {
  group('Profile Quota Helpers', () {
    test('formatBytes formats various byte sizes correctly', () {
      expect(Profile.formatBytes(0), '0 B');
      expect(Profile.formatBytes(512), '512 B');
      expect(Profile.formatBytes(1024), '1.0 KB');
      expect(Profile.formatBytes(10 * 1024 * 1024), '10 MB');
      expect(Profile.formatBytes(4294967296), '4.0 GB');
      expect(Profile.formatBytes(10737418240), '10 GB');
    });

    test('remainingWeeklyBytes computes remaining bandwidth', () {
      final now = DateTime.now();
      final profile = Profile(
        id: 'u1',
        displayName: 'Alice',
        isGuest: false,
        r2UploadBytes7d: 1024 * 1024 * 1024, // 1 GB
        r2UploadWindowStart: now.subtract(const Duration(days: 2)),
      );

      const weeklyLimit = 4 * 1024 * 1024 * 1024; // 4 GB
      expect(profile.remainingWeeklyBytes(weeklyLimit), 3 * 1024 * 1024 * 1024);
    });

    test('remainingWeeklyBytes resets if window start is older than 7 days', () {
      final now = DateTime.now();
      final profile = Profile(
        id: 'u1',
        displayName: 'Alice',
        isGuest: false,
        r2UploadBytes7d: 4 * 1024 * 1024 * 1024, // 4 GB
        r2UploadWindowStart: now.subtract(const Duration(days: 8)),
      );

      const weeklyLimit = 4 * 1024 * 1024 * 1024;
      expect(profile.remainingWeeklyBytes(weeklyLimit), weeklyLimit);
    });

    test('fromJson and copyWith preserve quota fields', () {
      final windowStart = DateTime.now().toUtc();
      final json = {
        'id': 'u1',
        'display_name': 'Alice',
        'is_guest': false,
        'email': 'alice@example.com',
        'r2_upload_bytes_7d': 500000,
        'r2_upload_window_start': windowStart.toIso8601String(),
        'r2_cooldown_until': null,
      };

      final profile = Profile.fromJson(json);
      expect(profile.r2UploadBytes7d, 500000);
      expect(profile.r2UploadWindowStart?.toIso8601String(), windowStart.toIso8601String());

      final updated = profile.copyWith(r2UploadBytes7d: 800000);
      expect(updated.r2UploadBytes7d, 800000);
      expect(updated.displayName, 'Alice');
    });
  });
}
