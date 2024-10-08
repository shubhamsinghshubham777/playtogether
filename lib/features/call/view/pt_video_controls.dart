import 'dart:async';

import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/utils.dart';

class PTVideoControls extends StatefulWidget {
  const PTVideoControls(
    this.player, {
    super.key,
    this.onPlayPause,
    this.onSeek,
  });

  final Player player;
  final void Function(bool, int)? onPlayPause;
  final void Function(int)? onSeek;

  @override
  State<PTVideoControls> createState() => _PTVideoControlsState();
}

class _PTVideoControlsState extends State<PTVideoControls> {
  bool playing = false;
  StreamSubscription<dynamic>? playingSubscription;

  Duration position = Duration.zero;
  StreamSubscription<dynamic>? positionSubscription;

  Duration duration = Duration.zero;
  StreamSubscription<dynamic>? durationSubscription;
  bool isDurationSliderDragging = false;
  double durationSliderDragValue = 0;

  bool showControls = false;

  bool isMediaLoaded = false;
  StreamSubscription<dynamic>? mediaTracksSubscription;

  @override
  void initState() {
    // Single state allocations
    final playerState = widget.player.state;
    setState(() {
      playing = playerState.playing;
      position = playerState.position;
      duration = playerState.duration;
      isMediaLoaded = playerState.playlist.medias.isNotEmpty;
    });

    // Stream subscriptions
    playingSubscription = widget.player.stream.playing.listen(
      (isPlaying) {
        setState(() => playing = isPlaying);
        _hideControls();
      },
    );
    positionSubscription = widget.player.stream.position.listen(
      (newPosition) => setState(() => position = newPosition),
    );
    durationSubscription = widget.player.stream.duration.listen(
      (newDuration) => setState(() => duration = newDuration),
    );
    mediaTracksSubscription = widget.player.stream.playlist.listen(
      (mediaTracks) {
        setState(() => isMediaLoaded = mediaTracks.medias.isNotEmpty);
      },
    );
    super.initState();
  }

  @override
  void dispose() {
    playingSubscription?.cancel();
    positionSubscription?.cancel();
    durationSubscription?.cancel();
    mediaTracksSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isMediaLoaded) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: 250.milliseconds,
      reverseDuration: 250.milliseconds,
      // MouseRegion is used for desktop platforms
      child: MouseRegion(
        key: ValueKey(showControls),
        onEnter: (_) => isDesktop ? setState(() => showControls = true) : null,
        onExit: (_) => isDesktop ? setState(() => showControls = false) : null,
        // GestureDetector is used for mobile platforms
        child: GestureDetector(
          onTap: isDesktop
              ? null
              : () {
                  setState(() => showControls = !showControls);
                  _hideControls();
                },
          behavior: HitTestBehavior.translucent,
          child: !showControls
              ? null
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(color: Colors.black38),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () {
                              final seekPosition = position - 10.seconds;
                              widget.player.seek(seekPosition);
                              widget.onSeek?.call(seekPosition.inMilliseconds);
                            },
                            icon: const Icon(Icons.replay_10, size: 28),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: IconButton(
                              onPressed: () {
                                widget.player.playOrPause();
                                widget.onPlayPause?.call(
                                  !playing,
                                  position.inMilliseconds,
                                );
                              },
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                                size: 64,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              final seekPosition = position + 10.seconds;
                              widget.player.seek(seekPosition);
                              widget.onSeek?.call(seekPosition.inMilliseconds);
                            },
                            icon: const Icon(Icons.forward_10, size: 28),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        height: 48,
                        child: Slider(
                          value: _durationSliderValue,
                          onChangeStart: (_) => setState(
                            () => isDurationSliderDragging = true,
                          ),
                          onChangeEnd: (newValue) {
                            final seekPosition =
                                (duration.inMilliseconds * newValue).round();

                            widget.player
                                .seek(Duration(milliseconds: seekPosition))
                                .then(
                                  (_) => setState(
                                    () => isDurationSliderDragging = false,
                                  ),
                                );

                            widget.onSeek?.call(seekPosition);
                          },
                          onChanged: (newValue) => setState(
                            () => durationSliderDragValue = newValue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  double get _durationSliderValue {
    final isUninitialised =
        position == Duration.zero && duration == Duration.zero;

    if (isUninitialised) return 0;
    if (isDurationSliderDragging) return durationSliderDragValue;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
  }

  void _hideControls({Duration after = const Duration(seconds: 3)}) {
    if (!isDesktop) {
      Future.delayed(after, () {
        if (playing && showControls) setState(() => showControls = false);
      });
    }
  }
}
