import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/widgets/media_sharing_prompt_dialog.dart';
import 'package:playtogether/rooms/widgets/media_sharing_toggle.dart';
import 'package:playtogether/rooms/widgets/sharing_progress_indicator.dart';

void main() {
  group('SharingProgressIndicator', () {
    testWidgets('renders progress percentage, speed and ETA', (tester) async {
      var cancelTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SharingProgressIndicator(
              fraction: 0.45,
              speedBps: 2.5 * 1024 * 1024, // 2.5 MB/s
              etaSeconds: 85,
              state: 'uploading',
              label: 'Uploading video...',
              onCancel: () => cancelTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Uploading video...'), findsOneWidget);
      expect(find.textContaining('45%'), findsOneWidget);
      expect(find.textContaining('2.5 MB/s'), findsOneWidget);
      expect(find.textContaining('1m 25s'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(cancelTapped, isTrue);
    });

    testWidgets('renders completed state when fraction is 1.0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SharingProgressIndicator(
              fraction: 1.0,
              speedBps: 0,
              etaSeconds: 0,
              state: 'ready',
              label: 'Ready to watch',
            ),
          ),
        ),
      );

      expect(find.text('Ready to watch'), findsOneWidget);
      expect(find.textContaining('100%'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('MediaSharingToggle', () {
    testWidgets('toggles value and displays tier badge', (tester) async {
      var currentValue = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return MediaSharingToggle(
                  enabled: currentValue,
                  canShare: true,
                  tierLabel: 'Free (2.5 GB/wk)',
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Share file with room'), findsOneWidget);
      expect(find.text('Free (2.5 GB/wk)'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(currentValue, isTrue);
    });

    testWidgets('shows upgrade button when sharing is disabled for tier', (tester) async {
      var upgradeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaSharingToggle(
              enabled: false,
              canShare: false,
              tierLabel: 'Guest',
              onUpgradeTap: () => upgradeTapped = true,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Share file with room'), findsOneWidget);
      expect(find.text('Upgrade'), findsOneWidget);

      await tester.tap(find.text('Upgrade'));
      expect(upgradeTapped, isTrue);
    });
  });

  group('MediaSharingPromptDialog', () {
    testWidgets('returns share selection and remember choice', (tester) async {
      MediaSharingPromptResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showMediaSharingPromptDialog(
                    context: context,
                    fileName: 'vacation.mp4',
                    fileSize: 150 * 1024 * 1024,
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Share with room?'), findsOneWidget);
      expect(find.textContaining('vacation.mp4'), findsOneWidget);
      expect(find.textContaining('150 MB'), findsOneWidget);

      // Check remember checkbox
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // Tap "Share with room"
      await tester.tap(find.text('Share with Room'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.shouldShare, isTrue);
      expect(result!.rememberChoice, isTrue);
    });

    testWidgets('returns local only selection', (tester) async {
      MediaSharingPromptResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showMediaSharingPromptDialog(
                    context: context,
                    fileName: 'movie.mkv',
                    fileSize: 500 * 1024 * 1024,
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play Locally Only'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.shouldShare, isFalse);
      expect(result!.rememberChoice, isFalse);
    });
  });
}
