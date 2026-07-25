import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/inputs.dart';
import 'package:playtogether/ui/pt_theme.dart';

class RoomControlBarActions {
  const RoomControlBarActions({
    required this.onPlayPause,
    required this.onSeek,
    required this.onSkip,
    required this.onMicToggle,
    required this.onCamToggle,
    required this.onAudioTracks,
    required this.onSubtitles,
    required this.onSwitchSource,
    required this.onOpenFile,
    required this.onVolume,
  });

  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSkip;
  final ValueChanged<bool> onMicToggle;
  final ValueChanged<bool> onCamToggle;
  final VoidCallback? onAudioTracks;
  final VoidCallback? onSubtitles;
  final VoidCallback onSwitchSource;
  final VoidCallback? onOpenFile;
  final ValueChanged<double> onVolume;
}

class RoomControlBar extends StatelessWidget {
  const RoomControlBar({
    super.key,
    required this.playing,
    required this.position,
    required this.duration,
    required this.volume,
    required this.micOn,
    required this.camOn,
    required this.avAvailable,
    required this.actions,
    this.compact = false,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool micOn;
  final bool camOn;
  final bool avAvailable;
  final RoomControlBarActions actions;
  final bool compact;

  double get _progress =>
      duration.inMilliseconds == 0 ? 0 : position.inMilliseconds / duration.inMilliseconds;

  void _seekTo(double v) =>
      actions.onSeek(Duration(milliseconds: (v * duration.inMilliseconds).round()));

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: compact ? 20 : 24,
      opacity: 0.6,
      blur: 32,
      baseColor: const Color(0xFF141022),
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 26, vertical: compact ? 14 : 18),
      child: Column(
        mainAxisSize: .min,
        spacing: compact ? 10 : 14,
        children: [
          Row(
            spacing: compact ? 10 : 16,
            children: [
              Text(_fmt(position), style: PTText.mono.copyWith(fontSize: compact ? 11 : 13)),
              Expanded(
                child: PTSlider(
                  value: _progress,
                  trackHeight: compact ? 4 : 5,
                  thumbRadius: compact ? 6 : 7,
                  onChanged: _seekTo,
                ),
              ),
              Text(
                _fmt(duration),
                style: PTText.mono.copyWith(fontSize: compact ? 11 : 13, color: PTColors.white(0.5)),
              ),
            ],
          ),
          compact ? _compactRow() : _fullRow(),
        ],
      ),
    );
  }

  Widget _fullRow() {
    return Row(
      children: [
        Row(
          spacing: 8,
          children: [
            if (avAvailable) ...[
              PTIconButton(
                icon: Symbols.mic_rounded,
                active: micOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                size: 42,
                tooltip: micOn ? 'Mute mic' : 'Mic on',
                onPressed: () => actions.onMicToggle(!micOn),
              ),
              PTIconButton(
                icon: Symbols.videocam_rounded,
                active: camOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                size: 42,
                tooltip: camOn ? 'Camera off' : 'Camera on',
                onPressed: () => actions.onCamToggle(!camOn),
              ),
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: PTColors.white(0.12),
              ),
            ],
            PTIconButton(
              icon: Symbols.audiotrack_rounded,
              glass: false,
              borderRadius: BorderRadius.circular(12),
              size: 42,
              iconSize: 22,
              tooltip: 'Audio track',
              onPressed: actions.onAudioTracks,
            ),
            PTIconButton(
              icon: Symbols.subtitles_rounded,
              glass: false,
              borderRadius: BorderRadius.circular(12),
              size: 42,
              iconSize: 22,
              tooltip: 'Subtitles',
              onPressed: actions.onSubtitles,
            ),
          ],
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: .center,
            spacing: 20,
            children: [
              PTIconButton(
                icon: Symbols.replay_10_rounded,
                glass: false,
                iconSize: 26,
                onPressed: () => actions.onSkip(const Duration(seconds: -10)),
              ),
              PTPlayButton(playing: playing, onPressed: actions.onPlayPause),
              PTIconButton(
                icon: Symbols.forward_10_rounded,
                glass: false,
                iconSize: 26,
                onPressed: () => actions.onSkip(const Duration(seconds: 10)),
              ),
            ],
          ),
        ),
        Row(
          spacing: 8,
          children: [
            PTIconButton(
              icon: Symbols.smart_display_rounded,
              glass: false,
              borderRadius: BorderRadius.circular(12),
              size: 42,
              iconSize: 22,
              tooltip: 'Switch source',
              onPressed: actions.onSwitchSource,
            ),
            if (actions.onOpenFile != null)
              PTIconButton(
                icon: Symbols.folder_open_rounded,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                size: 42,
                iconSize: 22,
                tooltip: 'Open file',
                onPressed: actions.onOpenFile,
              ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Row(
                spacing: 10,
                children: [
                  Icon(Symbols.volume_up_rounded, size: 20, fill: 1, color: PTColors.white(0.75)),
                  SizedBox(
                    width: 110,
                    child: PTSlider(
                      value: volume,
                      trackHeight: 4,
                      thumbRadius: 5.5,
                      onChanged: actions.onVolume,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _compactRow() {
    return Row(
      children: [
        if (avAvailable)
          Row(
            spacing: 8,
            children: [
              PTIconButton(
                icon: Symbols.mic_rounded,
                active: micOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                iconSize: 20,
                onPressed: () => actions.onMicToggle(!micOn),
              ),
              PTIconButton(
                icon: Symbols.videocam_rounded,
                active: camOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                iconSize: 20,
                onPressed: () => actions.onCamToggle(!camOn),
              ),
            ],
          ),
        Expanded(
          child: Row(
            mainAxisAlignment: .center,
            spacing: 14,
            children: [
              PTIconButton(
                icon: Symbols.replay_10_rounded,
                glass: false,
                iconSize: 24,
                onPressed: () => actions.onSkip(const Duration(seconds: -10)),
              ),
              PTPlayButton(playing: playing, size: 52, onPressed: actions.onPlayPause),
              PTIconButton(
                icon: Symbols.forward_10_rounded,
                glass: false,
                iconSize: 24,
                onPressed: () => actions.onSkip(const Duration(seconds: 10)),
              ),
            ],
          ),
        ),
        PTIconButton(
          icon: Symbols.subtitles_rounded,
          glass: false,
          borderRadius: BorderRadius.circular(12),
          iconSize: 21,
          onPressed: actions.onSubtitles,
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
