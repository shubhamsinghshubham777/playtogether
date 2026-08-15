import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/profile/subscription_screen.dart';
import 'package:playtogether/ui/responsive.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    builder: buildResponsiveWrapper,
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  group('SubscriptionScreen', () {
    testWidgets('desktop renders Go Premium button for free users', (tester) async {
      await tester.pumpWidget(_wrap(const SubscriptionScreen(desktopOverride: true)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PlayTogether Premium'), findsOneWidget);
      expect(find.text('Go Premium'), findsOneWidget);
      expect(find.text("You'll be taken to our website to complete your purchase."), findsOneWidget);
      expect(find.byIcon(Symbols.workspace_premium_rounded), findsWidgets);
    });

    testWidgets('mobile renders plain text info instead of button', (tester) async {
      await tester.pumpWidget(_wrap(const SubscriptionScreen(desktopOverride: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PlayTogether Premium'), findsOneWidget);
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('Subscriptions are managed on our website.'), findsOneWidget);
    });
  });
}
