import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/ui/buttons.dart';

void main() {
  group('RoomControlBar AV Controls (TDD)', () {
    testWidgets('disables mic and cam buttons with comic tooltips when avEnabled is false', (tester) async {
      bool micToggled = false;
      bool camToggled = false;

      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) => micToggled = true,
        onCamToggle: (_) => camToggled = true,
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              camAvailable: true,
              avEnabled: false,
              actions: actions,
            ),
          ),
        ),
      );

      // Find mic & cam PTIconButtons
      final micFinder = find.widgetWithIcon(PTIconButton, Symbols.mic_rounded);
      final camFinder = find.widgetWithIcon(PTIconButton, Symbols.videocam_rounded);

      expect(micFinder, findsOneWidget);
      expect(camFinder, findsOneWidget);

      final micButton = tester.widget<PTIconButton>(micFinder);
      final camButton = tester.widget<PTIconButton>(camFinder);

      expect(micButton.onPressed, isNull);
      expect(camButton.onPressed, isNull);

      // Verify comic tooltips
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == RoomControlBar.soloMicTooltip),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == RoomControlBar.soloCamTooltip),
        findsOneWidget,
      );

      // Tapping disabled buttons should not fire callbacks
      await tester.tap(micFinder);
      await tester.tap(camFinder);
      await tester.pump();

      expect(micToggled, isFalse);
      expect(camToggled, isFalse);
    });

    testWidgets('enables mic and cam buttons with standard tooltips when avEnabled is true', (tester) async {
      bool? micToggledValue;
      bool? camToggledValue;

      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (v) => micToggledValue = v,
        onCamToggle: (v) => camToggledValue = v,
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              camAvailable: true,
              avEnabled: true,
              actions: actions,
            ),
          ),
        ),
      );

      final micFinder = find.widgetWithIcon(PTIconButton, Symbols.mic_rounded);
      final camFinder = find.widgetWithIcon(PTIconButton, Symbols.videocam_rounded);

      expect(micFinder, findsOneWidget);
      expect(camFinder, findsOneWidget);

      final micButton = tester.widget<PTIconButton>(micFinder);
      final camButton = tester.widget<PTIconButton>(camFinder);

      expect(micButton.onPressed, isNotNull);
      expect(camButton.onPressed, isNotNull);

      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Mic on'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Camera on'),
        findsOneWidget,
      );

      await tester.tap(micFinder);
      await tester.pump();
      expect(micToggledValue, isTrue);

      await tester.tap(camFinder);
      await tester.pump();
      expect(camToggledValue, isTrue);
    });

    testWidgets('shows Mute mic and Camera off when micOn and camOn are true', (tester) async {
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: true,
              camOn: true,
              avAvailable: true,
              camAvailable: true,
              avEnabled: true,
              actions: actions,
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Mute mic'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Camera off'),
        findsOneWidget,
      );
    });

    testWidgets('compact mode disables mic and cam with comic tooltips when avEnabled is false', (tester) async {
      bool micToggled = false;
      bool camToggled = false;

      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) => micToggled = true,
        onCamToggle: (_) => camToggled = true,
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              camAvailable: true,
              avEnabled: false,
              compact: true,
              actions: actions,
            ),
          ),
        ),
      );

      final micFinder = find.widgetWithIcon(PTIconButton, Symbols.mic_rounded);
      final camFinder = find.widgetWithIcon(PTIconButton, Symbols.videocam_rounded);

      expect(micFinder, findsOneWidget);
      expect(camFinder, findsOneWidget);

      final micButton = tester.widget<PTIconButton>(micFinder);
      final camButton = tester.widget<PTIconButton>(camFinder);

      expect(micButton.onPressed, isNull);
      expect(camButton.onPressed, isNull);

      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == RoomControlBar.soloMicTooltip),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == RoomControlBar.soloCamTooltip),
        findsOneWidget,
      );

      await tester.tap(micFinder);
      await tester.tap(camFinder);
      await tester.pump();

      expect(micToggled, isFalse);
      expect(camToggled, isFalse);
    });

    testWidgets('hides mic and cam buttons entirely when avAvailable is false', (tester) async {
      final actions = RoomControlBarActions(
        onPlayPause: () {},
        onSeek: (_) {},
        onSkip: (_) {},
        onMicToggle: (_) {},
        onCamToggle: (_) {},
        onAudioTracks: () {},
        onSubtitles: () {},
        onSwitchSource: () {},
        onOpenFile: () {},
        onVolume: (_) {},
        onToggleMute: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: false,
              position: Duration.zero,
              duration: const Duration(minutes: 10),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: false,
              camAvailable: true,
              avEnabled: true,
              actions: actions,
            ),
          ),
        ),
      );

      expect(find.widgetWithIcon(PTIconButton, Symbols.mic_rounded), findsNothing);
      expect(find.widgetWithIcon(PTIconButton, Symbols.videocam_rounded), findsNothing);
    });
  });
}
