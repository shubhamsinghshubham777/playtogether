import 'dart:async';

import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

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

  @override
  void initState() {
    playingSubscription = widget.player.stream.playing.listen(
      (isPlaying) {
        setState(() => playing = isPlaying);
      },
    );
    positionSubscription = widget.player.stream.position.listen(
      (newPosition) {
        setState(() => position = newPosition);
      },
    );
    super.initState();
  }

  @override
  void dispose() {
    playingSubscription?.cancel();
    positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  final seekPosition = position - 10.seconds;
                  widget.player.seek(seekPosition);
                  widget.onSeek?.call(seekPosition.inMilliseconds);
                },
                icon: const Icon(Icons.replay_10),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: IconButton(
                  onPressed: () {
                    widget.player.playOrPause();
                    widget.onPlayPause?.call(!playing, position.inMilliseconds);
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
              ),
              IconButton(
                onPressed: () {
                  final seekPosition = position + 10.seconds;
                  widget.player.seek(seekPosition);
                  widget.onSeek?.call(seekPosition.inMilliseconds);
                },
                icon: const Icon(Icons.forward_10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
