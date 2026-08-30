import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/media_quota_dialog.dart';

void main() {
  group('MediaQuotaDialog', () {
    testWidgets('renders media quota dialog body with tier explanations', (tester) async {
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
      expect(find.text('How Quotas Work'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Rolling 7-Day Window'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('Free Plan')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Premium Plan'),
        ),
        findsOneWidget,
      );
    });
  });
}
