import 'dart:async';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:playtogether/chat/chat_box.dart';
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

  bool _isChatOpen = false;
  int _unreadCount = 0;
  bool _isPeerOnline = false;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _presenceSubscription;

  @override
  void initState() {
    super.initState();
    pickVideo();
    _isPeerOnline = widget.syncService.isPeerOnline;
    _chatSubscription = widget.syncService.chatMessages.listen((_) {
      if (!_isChatOpen) {
        setState(() => _unreadCount++);
      }
    });
    _presenceSubscription = widget.syncService.peerOnlineStream.listen((isOnline) {
      setState(() => _isPeerOnline = isOnline);
    });
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _presenceSubscription?.cancel();
    super.dispose();
  }

  void _toggleChat() {
    setState(() {
      _isChatOpen = !_isChatOpen;
      if (_isChatOpen) _unreadCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              Video(
                controller: controller,
                controls: (_) => _PTVideoPlayerControls(widget.player, widget.syncService),
                subtitleViewConfiguration: SubtitleViewConfiguration(padding: EdgeInsets.all(32)),
              ),
              if (_isPeerOnline)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Online', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 16,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Badge(
                    isLabelVisible: _unreadCount > 0,
                    label: Text('$_unreadCount'),
                    child: IconButton.filled(
                      onPressed: _toggleChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ClipRect(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _isChatOpen ? screenWidth * 0.35 : 0,
            constraints: BoxConstraints(maxWidth: 300),
            child: _isChatOpen
                ? PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) _toggleChat();
                    },
                    child: ChatBox(syncService: widget.syncService, onClose: _toggleChat),
                  )
                : null,
          ),
        ),
      ],
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

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final controlsWidget = AnimatedSwitcher(
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
                      mainAxisAlignment: .spaceBetween,
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
                              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
                                  Container(
                                    width: 150,
                                    margin: EdgeInsets.only(right: 16),
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
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _isMobile
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => showControls = !showControls),
                child: controlsWidget,
              )
            : Focus(
                autofocus: true,
                onKeyEvent: handleKeyEvent,
                child: MouseRegion(
                  onEnter: (_) => setState(() => showControls = true),
                  onExit: (_) => setState(() => showControls = false),
                  child: controlsWidget,
                ),
              ),
      ),
    );
  }

  KeyEventResult handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        widget.player.playOrPause();
        if (playing.value) {
          widget.syncService.broadcastPause();
        } else {
          widget.syncService.broadcastPlay();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        final newPos = position.value - Duration(seconds: 5);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        final newPos = position.value + Duration(seconds: 5);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        widget.player.setVolume(volume.value + 10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.player.setVolume(volume.value - 10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyJ:
        final newPos = position.value - Duration(seconds: 10);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        final newPos = position.value + Duration(seconds: 10);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }
}
