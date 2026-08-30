import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/extend_room_dialog.dart';

Future<void> _open(
  WidgetTester tester, {
  VoidCallback? onSignIn,
  VoidCallback? onUpgrade,
  VoidCallback? onNotify,
  bool? desktopOverride,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: SizedBox(
                  width: 430,
                  child: PremiumTeaseDialog(
                    headline: 'Sign in for more time',
                    body: 'Guest rooms run for an hour and stop there.',
                    perks: const ['Rooms that run for four hours, not one'],
                    onNotify: onNotify,
                    onUpgrade: onUpgrade,
                    onSignIn: onSignIn,
                    desktopOverride: desktopOverride,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('PremiumTeaseDialog', () {
    testWidgets('offers a real sign-in when one is available, not a waitlist', (tester) async {
      await _open(tester, onSignIn: () {});

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('Maybe later'), findsOneWidget);
    });

    testWidgets('runs the sign-in and closes the dialog', (tester) async {
      var signedIn = 0;
      await _open(tester, onSignIn: () => signedIn++);

      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();

      expect(signedIn, 1);
      expect(find.byType(PremiumTeaseDialog), findsNothing);
    });

    testWidgets('offers Go Premium on desktop', (tester) async {
      var upgraded = 0;
      await _open(tester, desktopOverride: true, onUpgrade: () => upgraded++);

      expect(find.text('Sign in with Google'), findsNothing);
      expect(find.text('Go Premium'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);

      await tester.tap(find.text('Go Premium'));
      await tester.pumpAndSettle();

      expect(upgraded, 1);
      expect(find.byType(PremiumTeaseDialog), findsNothing);
    });

    testWidgets('renders plain text on mobile', (tester) async {
      await _open(tester, desktopOverride: false);

      expect(find.text('Sign in with Google'), findsNothing);
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('Subscriptions are managed on our website.'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(PremiumTeaseDialog), findsNothing);
    });
  });
}
