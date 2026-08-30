import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/media_quota_dialog.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';

void main() {
  group('MediaQuotaDialog', () {
    tearDown(() {
      ProfileService.instance.setProfileForTesting(null);
      EntitlementService.instance.setLimitsForTesting(null);
    });

    testWidgets('renders guest view with Google sign-in and Go Premium CTAs', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'guest-1', displayName: 'Guest-1234', isGuest: true),
      );
      EntitlementService.instance.setLimitsForTesting(
        const TierLimits(
          tier: kGuestTier,
          maxLiveRooms: 1,
          maxMembers: 4,
          maxSessionMinutes: 60,
          maxTotalSessionMinutes: 60,
          avLevel: .none,
          persistentRoomCap: 0,
          dormantHours: 0,
          freeExtensionMinutes: 0,
          mediaSharing: 'none',
          mediaSharingWeeklyBytes: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(child: SingleChildScrollView(child: MediaQuotaDialogBody())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media Sharing Quota'), findsOneWidget);
      expect(find.text('Sign in to unlock weekly quota'), findsOneWidget);
      expect(find.text('How Quotas Work'), findsOneWidget);
      expect(find.text('Sign in with Google (Free 2.5 GB)'), findsOneWidget);
      expect(find.text('Go Premium (Unlimited)'), findsOneWidget);
    });

    testWidgets('renders signed-in free user view with quota usage and upgrade button', (
      tester,
    ) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-1',
          displayName: 'Alex',
          isGuest: false,
          r2UploadBytes7d: 500 * 1024 * 1024,
        ),
      );
      EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(child: SingleChildScrollView(child: MediaQuotaDialogBody())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media Sharing Quota'), findsOneWidget);
      expect(find.text('7-Day Rolling Usage'), findsOneWidget);
      expect(find.text('Get Unlimited with Premium'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('renders premium user view with unlimited status', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(id: 'user-2', displayName: 'Sam', isGuest: false),
      );
      EntitlementService.instance.setLimitsForTesting(
        const TierLimits(
          tier: kPremiumTier,
          maxLiveRooms: 20,
          maxMembers: 16,
          maxSessionMinutes: 240,
          maxTotalSessionMinutes: 1440,
          avLevel: .video,
          persistentRoomCap: 20,
          dormantHours: 24,
          freeExtensionMinutes: 0,
          mediaSharing: 'full',
          mediaSharingWeeklyBytes: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0D0B14)),
          home: const Scaffold(
            body: Center(child: SingleChildScrollView(child: MediaQuotaDialogBody())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media Sharing Quota'), findsOneWidget);
      expect(find.text('Unlimited with Premium'), findsOneWidget);
      expect(
        find.text('No upload limits! Share videos up to 10.0 GB each with high-speed priority.'),
        findsOneWidget,
      );
      expect(find.text('Got it'), findsOneWidget);
    });
  });
}
