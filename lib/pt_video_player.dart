import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PTVideoPlayer extends StatefulWidget {
  const PTVideoPlayer(this.player, {super.key});

  final Player player;

  @override
  State<PTVideoPlayer> createState() => _PTVideoPlayerState();
}

class _PTVideoPlayerState extends State<PTVideoPlayer> {
  late final controller = VideoController(widget.player);

  @override
  void initState() {
    pickVideo();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Video(controller: controller, controls: (_) => _PTVideoPlayerControls(widget.player));
  }

  Future<void> pickVideo() async {
    const XTypeGroup videoTypeGroup = XTypeGroup(label: 'Videos', extensions: ['mp4', 'mkv']);
    final response = await FastFilePicker.pickFile(acceptedTypeGroups: [videoTypeGroup]);
    final uri = response?.uri ?? response?.path;
    if (uri != null) await widget.player.open(Media(uri), play: false);
  }
}

class _PTVideoPlayerControls extends StatefulWidget {
  const _PTVideoPlayerControls(this.player);

  final Player player;

  @override
  State<_PTVideoPlayerControls> createState() => _PTVideoPlayerControlsState();
}

class _PTVideoPlayerControlsState extends State<_PTVideoPlayerControls> {
  final showControls = ValueNotifier(true);
  final playing = ValueNotifier(false);
  final duration = ValueNotifier(Duration.zero);
  final position = ValueNotifier(Duration.zero);
  final volume = ValueNotifier(100.0);

  @override
  void initState() {
    super.initState();

    final state = widget.player.state;
    playing.value = state.playing;
    duration.value = state.duration;
    position.value = state.position;
    volume.value = state.volume;

    final stream = widget.player.stream;
    stream.playing.listen((playing) => this.playing.value = playing);
    stream.duration.listen((duration) => this.duration.value = duration);
    stream.position.listen((position) => this.position.value = position);
    stream.volume.listen((volume) => this.volume.value = volume);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: handleKeyEvent,
      child: Column(
        mainAxisSize: .min,
        children: [
          ValueListenableBuilder(
            valueListenable: duration,
            builder: (context, duration, _) => ValueListenableBuilder(
              valueListenable: position,
              builder: (context, position, _) {
                return Row(
                  children: [Text('${formatDuration(position)}/${formatDuration(duration)}')],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String formatDuration(Duration duration) {
    // Use .abs() to handle negative durations if necessary
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    // We use remainder(60) to get only the minutes/seconds within the hour/minute
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  KeyEventResult handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case .space:
          widget.player.playOrPause();
          break;
        case .arrowLeft:
          widget.player.seek(position.value - Duration(seconds: 5));
          break;
        case .arrowRight:
          widget.player.seek(position.value + Duration(seconds: 5));
          break;
        case .arrowUp:
          widget.player.setVolume(volume.value + 10);
          break;
        case .arrowDown:
          widget.player.setVolume(volume.value - 10);
          break;
        case .keyK:
          widget.player.playOrPause();
          break;
        case .keyJ:
          widget.player.seek(position.value - Duration(seconds: 10));
          break;
        case .keyL:
          widget.player.seek(position.value + Duration(seconds: 10));
          break;
      }
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }
}
