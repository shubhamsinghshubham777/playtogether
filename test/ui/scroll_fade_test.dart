import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/ui/scroll_fade.dart';

double _scrimOpacity(WidgetTester tester) {
  final opacity = tester.widget<Opacity>(
    find.descendant(of: find.byType(ScrollFadeEdge), matching: find.byType(Opacity)),
  );
  return opacity.opacity;
}

Future<void> _pump(WidgetTester tester, {VoidCallback? onTapTop}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: ScrollFadeEdge(
            height: 60,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: onTapTop,
                    child: Container(height: 60, color: const Color(0xFF123456)),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ScrollFadeEdge', () {
    testWidgets('stays invisible at rest', (tester) async {
      await _pump(tester);
      expect(_scrimOpacity(tester), 0);
    });

    testWidgets('ramps in with the first pixels of scroll', (tester) async {
      await _pump(tester);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -30));
      await tester.pump();
      expect(_scrimOpacity(tester), closeTo(0.5, 0.01));

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();
      expect(_scrimOpacity(tester), 1);
    });

    testWidgets('never eats taps on the content beneath it', (tester) async {
      var tapped = false;
      await _pump(tester, onTapTop: () => tapped = true);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -20));
      await tester.pump();

      await tester.tapAt(tester.getTopLeft(find.byType(ScrollFadeEdge)) + const Offset(50, 10));
      expect(tapped, isTrue);
    });
  });
}
