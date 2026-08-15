import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/profile/entitlement_service.dart';

void main() {
  group('EntitlementService', () {
    test('defaults to free tier when limits not loaded', () {
      expect(EntitlementService.instance.tier, kFreeTier);
      expect(EntitlementService.instance.isPremium, isFalse);
      expect(EntitlementService.instance.limitsOrFallback.maxSessionMinutes, 240);
    });

    test('clear resets limits and notifies', () {
      var notified = 0;
      EntitlementService.instance.addListener(() => notified++);
      EntitlementService.instance.clear();
      expect(EntitlementService.instance.limits, isNull);
    });
  });
}
