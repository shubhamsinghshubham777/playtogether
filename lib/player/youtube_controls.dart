import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as yt;

class YouTubeControls extends StatefulWidget {
  const YouTubeControls({
    super.key,
    required this.controller,
    required this.syncService,
    required this.onSwitchToLocal,
    required this.onChangeUrl,
  });

  final yt.YoutubePlayerController controller;
  final SyncService syncService;
  final VoidCallback onSwitchToLocal;
  final VoidCallback onChangeUrl;

  @override
  State<YouTubeControls> createState() => _YouTubeControlsState();
}

class _YouTubeControlsState extends State<YouTubeControls> {
  bool showControls = true;
  bool _isDragging = false;
  double _draggingValue = 0.0;
  final volume = ValueNotifier(100.0);

  @override
  void dispose() {
    volume.dispose();
    super.dispose();
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
              alignment: Alignment.bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colors.surfaceContainer,
                ),
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    Row(
                      spacing: 24,
                      children: [
                        // Mode Switch Button
                        Center(
                          child: IconButton(
                            onPressed: widget.onSwitchToLocal,
                            icon: Icon(Icons.video_file),
                            iconSize: 32,
                            tooltip: 'Switch to local video',
                          ),
                        ),

                        // Change URL Button
                        Center(
                          child: IconButton(
                            onPressed: widget.onChangeUrl,
                            icon: Icon(Icons.link),
                            iconSize: 32,
                            tooltip: 'Change YouTube URL',
                          ),
                        ),

                        // Play/Pause Button using YouTube widget
                        Center(
                          child: _SyncedPlayPauseButton(
                            controller: widget.controller,
                            syncService: widget.syncService,
                          ),
                        ),

                        // Balance spacers for centering play/pause button
                        SizedBox.shrink(),
                        SizedBox.shrink(),
                      ].map((child) => Expanded(child: child)).toList(),
                    ),

                    // Progress section with custom slider
                    ValueListenableBuilder(
                      valueListenable: widget.controller,
                      builder: (context, value, child) {
                        final position = value.position;
                        final duration = widget.controller.metadata.duration;
                        final displayPosition = _isDragging
                            ? Duration(milliseconds: _draggingValue.toInt())
                            : position;

                        return Row(
                          spacing: 8,
                          children: [
                            // Current position
                            Text(_formatDuration(displayPosition), style: TextStyle(fontSize: 14)),

                            Text(' / ', style: TextStyle(fontSize: 14)),

                            // Total duration
                            Text(_formatDuration(duration), style: TextStyle(fontSize: 14)),

                            SizedBox(width: 16),

                            // Custom slider for sync control
                            Expanded(
                              child: Slider(
                                value:
                                    (_isDragging
                                            ? _draggingValue
                                            : position.inMilliseconds.toDouble())
                                        .clamp(0.0, duration.inMilliseconds.toDouble()),
                                max: duration.inMilliseconds.toDouble(),
                                onChanged: (value) {
                                  // Only update visual state during drag
                                  setState(() {
                                    _isDragging = true;
                                    _draggingValue = value;
                                  });
                                },
                                onChangeEnd: (value) {
                                  // Perform actual seek and broadcast when user releases
                                  final newPosition = Duration(milliseconds: value.toInt());
                                  widget.controller.seekTo(newPosition);
                                  widget.controller.pause();
                                  widget.syncService.broadcastSeek(newPosition);
                                  setState(() => _isDragging = false);
                                },
                              ),
                            ),

                            // Volume section
                            ValueListenableBuilder(
                              valueListenable: volume,
                              builder: (context, vol, _) => Row(
                                spacing: 8,
                                children: [
                                  Icon(Icons.volume_up),
                                  Container(
                                    width: 150,
                                    margin: EdgeInsets.only(right: 16),
                                    child: Slider(
                                      padding: EdgeInsets.zero,
                                      value: (vol / 100).clamp(0, 1),
                                      // JS volume injection is unsupported on iOS
                                      onChanged: defaultTargetPlatform == .iOS
                                          ? null
                                          : (value) {
                                              final newVolume = (value * 100);
                                              volume.value = newVolume;
                                              widget.controller.setVolume(newVolume.toInt());
                                            },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '$minutes:${twoDigits(seconds)}';
    }
  }

  KeyEventResult handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final currentPosition = widget.controller.value.position;
    final isPlaying = widget.controller.value.playerState == yt.PlayerState.playing;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        if (isPlaying) {
          widget.controller.pause();
          widget.syncService.broadcastPause();
          widget.syncService.broadcastSeek(currentPosition);
        } else {
          widget.controller.play();
          widget.syncService.broadcastPlay();
          widget.syncService.broadcastSeek(currentPosition);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        final newPos = currentPosition - Duration(seconds: 5);
        widget.controller.seekTo(newPos);
        widget.controller.pause();
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        final newPos = currentPosition + Duration(seconds: 5);
        widget.controller.seekTo(newPos);
        widget.controller.pause();
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        final newVolumeUp = (volume.value + 10).clamp(0, 100).toDouble();
        volume.value = newVolumeUp;
        widget.controller.setVolume(newVolumeUp.toInt());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        final newVolumeDown = (volume.value - 10).clamp(0, 100).toDouble();
        volume.value = newVolumeDown;
        widget.controller.setVolume(newVolumeDown.toInt());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyJ:
        final newPos = currentPosition - Duration(seconds: 10);
        widget.controller.seekTo(newPos);
        widget.controller.pause();
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        final newPos = currentPosition + Duration(seconds: 10);
        widget.controller.seekTo(newPos);
        widget.controller.pause();
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }
}

/// Custom play/pause button that syncs with YouTube state and broadcasts events
class _SyncedPlayPauseButton extends StatelessWidget {
  const _SyncedPlayPauseButton({required this.controller, required this.syncService});

  final yt.YoutubePlayerController controller;
  final SyncService syncService;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, child) {
        final isPlaying = value.playerState == yt.PlayerState.playing;

        return IconButton(
          onPressed: () {
            final currentPosition = value.position;
            if (isPlaying) {
              controller.pause();
              syncService.broadcastPause();
              syncService.broadcastSeek(currentPosition);
            } else {
              controller.play();
              syncService.broadcastPlay();
              syncService.broadcastSeek(currentPosition);
            }
          },
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          iconSize: 64,
        );
      },
    );
  }
}
