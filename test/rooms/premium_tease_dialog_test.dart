import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/widgets/extend_room_dialog.dart';

Future<void> _open(WidgetTester tester, {VoidCallback? onSignIn, VoidCallback? onNotify}) async {
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
                    onSignIn: onSignIn,
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
      expect(find.text('Keep me posted'), findsNothing);
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

    testWidgets('falls back to the waitlist when there is nothing to act on', (tester) async {
      var notified = 0;
      await _open(tester, onNotify: () => notified++);

      expect(find.text('Sign in with Google'), findsNothing);
      await tester.tap(find.text('Keep me posted'));
      await tester.pumpAndSettle();

      expect(notified, 1);
      expect(find.byType(PremiumTeaseDialog), findsNothing);
    });
  });
}
