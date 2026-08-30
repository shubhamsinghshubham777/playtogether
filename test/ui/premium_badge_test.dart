import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/ui/identity.dart';

Finder get _crown => find.byIcon(Symbols.crown_rounded);

Future<void> _pumpAvatar(WidgetTester tester, {required bool premium}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: PTAvatar(userId: 'u1', displayName: 'Riya', size: 36, premium: premium),
        ),
      ),
    ),
  );
}

void main() {
  group('who wears a crown', () {
    test('premium does', () {
      expect(tierWearsCrown(kPremiumTier), isTrue);
    });

    test('free does not', () {
      expect(tierWearsCrown(kFreeTier), isFalse);
    });

    test('a guest never does, whatever a subscription row says', () {
      expect(tierWearsCrown(kGuestTier), isFalse);
    });

    test('an unresolved tier does not', () {
      expect(tierWearsCrown(null), isFalse);
    });

    test('premiumMembersFrom keeps only the premium ids', () {
      expect(
        premiumMembersFrom({'a': kPremiumTier, 'b': kFreeTier, 'c': kGuestTier, 'd': kPremiumTier}),
        {'a', 'd'},
      );
    });

    test('an empty room yields nobody', () {
      expect(premiumMembersFrom(const {}), isEmpty);
    });
  });

  group('PTAvatar', () {
    testWidgets('wears the crown when told it is premium', (tester) async {
      await _pumpAvatar(tester, premium: true);
      expect(_crown, findsOneWidget);
    });

    testWidgets('has no crown by default', (tester) async {
      await _pumpAvatar(tester, premium: false);
      expect(_crown, findsNothing);
    });

    testWidgets('keeps the presence dot alongside the crown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PTAvatar(
                userId: 'u1',
                displayName: 'Riya',
                size: 36,
                presence: true,
                premium: true,
              ),
            ),
          ),
        ),
      );
      expect(_crown, findsOneWidget);
      expect(find.byType(Stack), findsWidgets);
    });
  });

  group('PremiumBadge', () {
    testWidgets('reads as Premium', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: PremiumBadge())),
        ),
      );
      expect(find.text('Premium'), findsOneWidget);
      expect(_crown, findsOneWidget);
    });
  });
}
