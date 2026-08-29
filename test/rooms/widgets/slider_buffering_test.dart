import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/widgets/room_control_bar.dart';
import 'package:playtogether/ui/inputs.dart';

RoomControlBarActions _dummyActions() => RoomControlBarActions(
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

void main() {
  group('PTSlider Buffering', () {
    testWidgets('renders PTSlider with and without bufferedValue', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PTSlider(
                  value: 0.3,
                  bufferedValue: 0.6,
                  onChanged: (_) {},
                ),
                PTSlider(
                  value: 0.3,
                  bufferedValue: null,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(PTSlider), findsNWidgets(2));
    });

    testWidgets('RoomControlBar computes buffered progress when streaming', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: true,
              position: const Duration(minutes: 5),
              duration: const Duration(minutes: 10),
              bufferedPosition: const Duration(minutes: 7),
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              actions: _dummyActions(),
            ),
          ),
        ),
      );

      final slider = tester.widget<PTSlider>(find.byType(PTSlider).first);
      expect(slider.value, closeTo(0.5, 0.01));
      expect(slider.bufferedValue, closeTo(0.7, 0.01));
    });

    testWidgets('RoomControlBar leaves bufferedValue null for local files', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlBar(
              playing: true,
              position: const Duration(minutes: 5),
              duration: const Duration(minutes: 10),
              bufferedPosition: null, // local file playback
              volume: 1.0,
              micOn: false,
              camOn: false,
              avAvailable: true,
              actions: _dummyActions(),
            ),
          ),
        ),
      );

      final slider = tester.widget<PTSlider>(find.byType(PTSlider).first);
      expect(slider.value, closeTo(0.5, 0.01));
      expect(slider.bufferedValue, isNull);
    });
  });
}
