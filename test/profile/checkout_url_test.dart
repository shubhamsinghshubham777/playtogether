import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/profile/subscription_screen.dart';

void main() {
  group('checkout and account URLs', () {
    test('resolves debug localhost urls in test/debug mode', () {
      if (kDebugMode) {
        expect(checkoutUrl, 'http://localhost:3000/premium');
        expect(accountUrl, 'http://localhost:3000/account');
      } else {
        expect(checkoutUrl, 'https://playtogether.app/premium');
        expect(accountUrl, 'https://playtogether.app/account');
      }
    });
  });
}
