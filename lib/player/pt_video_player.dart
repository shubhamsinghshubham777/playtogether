import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:playtogether/player/chooser_dialog.dart';
import 'package:playtogether/player/progress_section.dart';
import 'package:playtogether/sync/sync_service.dart';

class PTVideoPlayer extends StatefulWidget {
  const PTVideoPlayer(this.player, this.syncService, {super.key});

  final Player player;
  final SyncService syncService;

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
    return Video(
      controller: controller,
      controls: (_) => _PTVideoPlayerControls(widget.player, widget.syncService),
      subtitleViewConfiguration: SubtitleViewConfiguration(padding: EdgeInsets.all(32)),
    );
  }

  Future<void> pickVideo() async {
    const XTypeGroup videoTypeGroup = XTypeGroup(label: 'Videos', extensions: ['mp4', 'mkv']);
    final response = await FastFilePicker.pickFile(acceptedTypeGroups: [videoTypeGroup]);
    final uri = response?.uri ?? response?.path;
    if (uri != null) await widget.player.open(Media(uri), play: false);
  }
}

class _PTVideoPlayerControls extends StatefulWidget {
  const _PTVideoPlayerControls(this.player, this.syncService);

  final Player player;
  final SyncService syncService;

  @override
  State<_PTVideoPlayerControls> createState() => _PTVideoPlayerControlsState();
}

class _PTVideoPlayerControlsState extends State<_PTVideoPlayerControls> {
  bool showControls = true;
  final playing = ValueNotifier(false);
  final duration = ValueNotifier(Duration.zero);
  final position = ValueNotifier(Duration.zero);
  final volume = ValueNotifier(100.0);
  final audioTracks = ValueNotifier(<AudioTrack>[]);
  final subtitleTracks = ValueNotifier(<SubtitleTrack>[]);

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
    stream.tracks.listen((tracks) {
      audioTracks.value = tracks.audio;
      subtitleTracks.value = tracks.subtitle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Focus(
      autofocus: true,
      onKeyEvent: handleKeyEvent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: MouseRegion(
          onEnter: (_) => setState(() => showControls = true),
          onExit: (_) => setState(() => showControls = false),
          child: AnimatedSwitcher(
            duration: Durations.short2,
            child: !showControls
                ? null
                : Align(
                    alignment: .bottomCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: colors.surfaceContainer,
                      ),
                      padding: EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: .min,
                        spacing: 16,
                        children: [
                          Row(
                            mainAxisAlignment: .center,
                            spacing: 24,
                            children: [
                              // Audio Tracks Button
                              ValueListenableBuilder(
                                valueListenable: audioTracks,
                                builder: (context, audioTracks, _) {
                                  return IconButton(
                                    onPressed: audioTracks.isEmpty
                                        ? null
                                        : () => showDialog(
                                            context: context,
                                            builder: (context) => ChooserDialog(
                                              type: 'Audio',
                                              values: audioTracks,
                                              onChosen: (track) async {
                                                await widget.player.setAudioTrack(track);
                                                if (context.mounted) Navigator.of(context).pop();
                                              },
                                            ),
                                          ),
                                    icon: Icon(Icons.audiotrack_rounded),
                                    iconSize: 32,
                                  );
                                },
                              ),

                              // Play/Pause Button
                              ValueListenableBuilder(
                                valueListenable: playing,
                                builder: (context, playing, _) {
                                  return IconButton(
                                    onPressed: () {
                                      widget.player.playOrPause();
                                      if (playing) {
                                        widget.syncService.broadcastPause();
                                      } else {
                                        widget.syncService.broadcastPlay();
                                      }
                                    },
                                    icon: Icon(
                                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    ),
                                    iconSize: 64,
                                  );
                                },
                              ),

                              // Subtitle Tracks Button
                              ValueListenableBuilder(
                                valueListenable: subtitleTracks,
                                builder: (context, subtitleTracks, _) {
                                  return IconButton(
                                    onPressed: subtitleTracks.isEmpty
                                        ? null
                                        : () => showDialog(
                                            context: context,
                                            builder: (context) => ChooserDialog(
                                              type: 'Subtitle',
                                              values: subtitleTracks,
                                              onChosen: (track) async {
                                                await widget.player.setSubtitleTrack(track);
                                                if (context.mounted) Navigator.of(context).pop();
                                              },
                                            ),
                                          ),
                                    icon: Icon(Icons.subtitles),
                                    iconSize: 32,
                                  );
                                },
                              ),
                            ],
                          ),
                          ValueListenableBuilder(
                            valueListenable: duration,
                            builder: (context, duration, _) => ValueListenableBuilder(
                              valueListenable: position,
                              builder: (context, position, _) {
                                return ProgressSection(
                                  position: position,
                                  duration: duration,
                                  onSeek: (newPosition) async {
                                    await widget.player.seek(newPosition);
                                    widget.syncService.broadcastSeek(newPosition);
                                  },
                                  volumeSection: ValueListenableBuilder(
                                    valueListenable: volume,
                                    builder: (context, volume, _) => Row(
                                      spacing: 8,
                                      children: [
                                        Icon(Icons.volume_up),
                                        SizedBox(
                                          width: 150,
                                          child: Slider(
                                            padding: EdgeInsets.zero,
                                            value: (volume / 100).clamp(0, 1),
                                            onChanged: (value) {
                                              widget.player.setVolume(value * 100);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  KeyEventResult handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case .space:
        case .keyK:
          widget.player.playOrPause();
          if (playing.value) {
            widget.syncService.broadcastPause();
          } else {
            widget.syncService.broadcastPlay();
          }
          break;
        case .arrowLeft:
          final newPos = position.value - Duration(seconds: 5);
          widget.player.seek(newPos);
          widget.syncService.broadcastSeek(newPos);
          break;
        case .arrowRight:
          final newPos = position.value + Duration(seconds: 5);
          widget.player.seek(newPos);
          widget.syncService.broadcastSeek(newPos);
          break;
        case .arrowUp:
          widget.player.setVolume(volume.value + 10);
          break;
        case .arrowDown:
          widget.player.setVolume(volume.value - 10);
          break;
        case .keyJ:
          final newPos = position.value - Duration(seconds: 10);
          widget.player.seek(newPos);
          widget.syncService.broadcastSeek(newPos);
          break;
        case .keyL:
          final newPos = position.value + Duration(seconds: 10);
          widget.player.seek(newPos);
          widget.syncService.broadcastSeek(newPos);
          break;
      }
      return .handled;
    }
    if (event is KeyRepeatEvent) return .handled;
    return .ignored;
  }
}
