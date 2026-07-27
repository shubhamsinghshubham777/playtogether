import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/inputs.dart';
import 'package:playtogether/ui/pt_motion.dart';
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
    this.openFileTooltip,
    required this.onVolume,
    required this.onToggleMute,
  });

  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSkip;
  final ValueChanged<bool> onMicToggle;
  final ValueChanged<bool> onCamToggle;
  final VoidCallback? onAudioTracks;
  final VoidCallback? onSubtitles;

  /// Null for members — choosing what the room watches is host-only (D1), and
  /// omitting the callback is how this kit hides an action.
  final VoidCallback? onSwitchSource;
  final VoidCallback? onOpenFile;

  /// Members get "Locate your copy of `<name>`" — their picker exists to find
  /// their own copy of the room's file, never to change what the room watches.
  final String? openFileTooltip;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;
}

class RoomControlBar extends StatefulWidget {
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
    this.transportEnabled = true,
    this.transportHint,
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

  /// Affordance only — the real enforcement lives at RoomScreen's
  /// `_playPause`/`_seek`/`_skip` choke points, which keyboard shortcuts and
  /// double-tap skip zones also go through.
  final bool transportEnabled;

  /// Why the transport is disabled, shown next to the controls.
  final String? transportHint;

  @override
  State<RoomControlBar> createState() => _RoomControlBarState();
}

class _RoomControlBarState extends State<RoomControlBar> {
  /// While scrubbing, the bar previews this value locally; the actual seek
  /// (and its room-wide broadcast) fires once, on release.
  double? _dragValue;

  /// Normalized 0–1 position under a hovering cursor (desktop only); drives the
  /// seek-preview chip. The chip escapes the glass panel's clip via [_sliderLink].
  double? _hoverValue;
  final _sliderLink = LayerLink();

  double get _progress => widget.duration.inMilliseconds == 0
      ? 0
      : widget.position.inMilliseconds / widget.duration.inMilliseconds;

  void _endScrub(double v) {
    setState(() => _dragValue = null);
    widget.actions.onSeek(Duration(milliseconds: (v * widget.duration.inMilliseconds).round()));
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final drag = _dragValue;
    final hover = _hoverValue;
    final shownPosition = drag == null ? widget.position : widget.duration * drag;
    final panel = GlassPanel(
      radius: compact ? 20 : 24,
      opacity: 0.6,
      blur: 32,
      baseColor: const Color(0xFF141022),
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 26, vertical: compact ? 14 : 18),
      // Two nested columns on purpose: the hint sits *outside* the spaced
      // column so its collapsed state costs nothing. As a spaced sibling, an
      // empty hint would still leave a row gap behind it.
      child: Column(
        mainAxisSize: .min,
        children: [
          Column(
            mainAxisSize: .min,
            spacing: compact ? 10 : 14,
            children: [
              Row(
                spacing: compact ? 10 : 16,
                children: [
                  Text(
                    _fmt(shownPosition),
                    style: PTText.mono.copyWith(fontSize: compact ? 11 : 13),
                  ),
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _sliderLink,
                      child: PTSlider(
                        value: drag ?? _progress,
                        trackHeight: compact ? 4 : 5,
                        thumbRadius: compact ? 6 : 7,
                        enabled: widget.transportEnabled,
                        onChanged: (v) => setState(() => _dragValue = v),
                        onChangeEnd: _endScrub,
                        onHover: (v) => setState(() => _hoverValue = v),
                      ),
                    ),
                  ),
                  Text(
                    _fmt(widget.duration),
                    style: PTText.mono.copyWith(
                      fontSize: compact ? 11 : 13,
                      color: PTColors.white(0.5),
                    ),
                  ),
                ],
              ),
              compact ? _compactRow() : _fullRow(),
            ],
          ),
          // Grows and collapses rather than appearing: the gate can flap, and
          // a bar that jumps a row height each time is worse than the hint.
          AnimatedSize(
            duration: PTMotion.functional(context, PTMotion.state),
            curve: PTMotion.enter,
            alignment: .topCenter,
            child: !widget.transportEnabled && widget.transportHint != null
                ? Padding(
                    padding: EdgeInsets.only(top: compact ? 10 : 14),
                    child: Text(
                      widget.transportHint!,
                      textAlign: .center,
                      // Media names get long; the overlay is where the full name is
                      // readable, this is only a nudge.
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: PTText.finePrint.copyWith(color: PTColors.white(0.55)),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );

    // The preview chip must escape the panel's ClipRRect, so it rides a
    // CompositedTransformFollower in an unclipped outer Stack rather than
    // living inside the panel. Hidden while scrubbing (the position text
    // already previews the drag) and until a duration is known.
    final showChip = hover != null && drag == null && widget.duration.inMilliseconds > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        panel,
        if (showChip)
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _sliderLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: Offset(hover * (_sliderLink.leaderSize?.width ?? 0), -8),
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: IgnorePointer(
                  // Rises into place on the first hover. It tracks the cursor
                  // instantly after that — the follower offset is not animated,
                  // so the chip never lags the pointer.
                  child: PTEntrance(
                    duration: PTMotion.hover,
                    offset: 6,
                    child: _previewChip(widget.duration * hover),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _previewChip(Duration position) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: PTColors.glassBase,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: PTColors.white(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(_fmt(position), style: PTText.mono.copyWith(fontSize: 12)),
    );
  }

  Widget _fullRow() {
    final actions = widget.actions;
    return Row(
      children: [
        Row(
          spacing: 8,
          children: [
            if (widget.avAvailable) ...[
              PTIconButton(
                icon: Symbols.mic_rounded,
                active: widget.micOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                size: 42,
                tooltip: widget.micOn ? 'Mute mic' : 'Mic on',
                onPressed: () => actions.onMicToggle(!widget.micOn),
              ),
              PTIconButton(
                icon: Symbols.videocam_rounded,
                active: widget.camOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                size: 42,
                tooltip: widget.camOn ? 'Camera off' : 'Camera on',
                onPressed: () => actions.onCamToggle(!widget.camOn),
              ),
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: PTColors.white(0.12),
              ),
            ],
            if (actions.onAudioTracks != null)
              PTIconButton(
                icon: Symbols.audiotrack_rounded,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                size: 42,
                iconSize: 22,
                tooltip: 'Audio track',
                onPressed: actions.onAudioTracks,
              ),
            if (actions.onSubtitles != null)
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
                spinOnPress: -40,
                onPressed: widget.transportEnabled
                    ? () => actions.onSkip(const Duration(seconds: -10))
                    : null,
              ),
              PTPlayButton(
                playing: widget.playing,
                onPressed: widget.transportEnabled ? actions.onPlayPause : null,
              ),
              PTIconButton(
                icon: Symbols.forward_10_rounded,
                glass: false,
                iconSize: 26,
                spinOnPress: 40,
                onPressed: widget.transportEnabled
                    ? () => actions.onSkip(const Duration(seconds: 10))
                    : null,
              ),
            ],
          ),
        ),
        Row(
          spacing: 8,
          children: [
            if (actions.onSwitchSource != null)
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
                tooltip: actions.openFileTooltip ?? 'Open file',
                onPressed: actions.onOpenFile,
              ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Row(
                spacing: 4,
                children: [
                  PTIconButton(
                    icon: widget.volume == 0
                        ? Symbols.volume_off_rounded
                        : Symbols.volume_up_rounded,
                    glass: false,
                    size: 36,
                    iconSize: 20,
                    tooltip: widget.volume == 0 ? 'Unmute' : 'Mute',
                    onPressed: actions.onToggleMute,
                  ),
                  SizedBox(
                    width: 110,
                    child: PTSlider(
                      value: widget.volume,
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
    final actions = widget.actions;
    return Row(
      children: [
        if (widget.avAvailable)
          Row(
            spacing: 8,
            children: [
              PTIconButton(
                icon: Symbols.mic_rounded,
                active: widget.micOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                iconSize: 20,
                onPressed: () => actions.onMicToggle(!widget.micOn),
              ),
              PTIconButton(
                icon: Symbols.videocam_rounded,
                active: widget.camOn,
                glass: false,
                borderRadius: BorderRadius.circular(12),
                iconSize: 20,
                onPressed: () => actions.onCamToggle(!widget.camOn),
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
                spinOnPress: -40,
                onPressed: widget.transportEnabled
                    ? () => actions.onSkip(const Duration(seconds: -10))
                    : null,
              ),
              PTPlayButton(
                playing: widget.playing,
                size: 52,
                onPressed: widget.transportEnabled ? actions.onPlayPause : null,
              ),
              PTIconButton(
                icon: Symbols.forward_10_rounded,
                glass: false,
                iconSize: 24,
                spinOnPress: 40,
                onPressed: widget.transportEnabled
                    ? () => actions.onSkip(const Duration(seconds: 10))
                    : null,
              ),
            ],
          ),
        ),
        // Source controls belong here too — this row is what portrait,
        // landscape and any narrow desktop window actually render, so leaving
        // them out of it left those layouts with no way to pick anything.
        if (actions.onSwitchSource != null)
          PTIconButton(
            icon: Symbols.smart_display_rounded,
            glass: false,
            borderRadius: BorderRadius.circular(12),
            iconSize: 21,
            tooltip: 'Switch source',
            onPressed: actions.onSwitchSource,
          ),
        if (actions.onOpenFile != null)
          PTIconButton(
            icon: Symbols.folder_open_rounded,
            glass: false,
            borderRadius: BorderRadius.circular(12),
            iconSize: 21,
            tooltip: actions.openFileTooltip ?? 'Open file',
            onPressed: actions.onOpenFile,
          ),
        if (actions.onAudioTracks != null)
          PTIconButton(
            icon: Symbols.audiotrack_rounded,
            glass: false,
            borderRadius: BorderRadius.circular(12),
            iconSize: 21,
            tooltip: 'Audio track',
            onPressed: actions.onAudioTracks,
          ),
        if (actions.onSubtitles != null)
          PTIconButton(
            icon: Symbols.subtitles_rounded,
            glass: false,
            borderRadius: BorderRadius.circular(12),
            iconSize: 21,
            tooltip: 'Subtitles',
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
