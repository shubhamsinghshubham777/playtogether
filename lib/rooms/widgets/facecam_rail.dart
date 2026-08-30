import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/av/livekit_service.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';

enum FacecamLayout { railLeft, stripTop, miniStackRight }

/// Facecam tiles per present member: live video when the member publishes a
/// cam track, avatar tile otherwise; self first with the violet ring.
///
/// People arriving and leaving is a social event, so tiles animate both ways:
/// departures are held in the tree for one [PTMotion.state] while they fade,
/// which is why this is stateful.
class FacecamRail extends StatefulWidget {
  const FacecamRail({
    super.key,
    required this.av,
    required this.present,
    required this.selfId,
    required this.layout,
    this.onHide,
    this.maxTiles = 4,
    this.showNames = true,
    this.premiumMembers = const {},
  });

  final LiveKitService av;
  final List<PresentMember> present;
  final String selfId;
  final FacecamLayout layout;
  final VoidCallback? onHide;
  final int maxTiles;
  final bool showNames;
  final Set<String> premiumMembers;

  @override
  State<FacecamRail> createState() => _FacecamRailState();
}

class _FacecamRailState extends State<FacecamRail> {
  /// Members that have gone but are still fading out, in their last known
  /// slot order so the rail doesn't reshuffle while they leave.
  final _leaving = <String, PresentMember>{};
  final _leavingTimers = <String, Timer>{};

  List<PresentMember> get _ordered => [
    ...widget.present.where((m) => m.userId == widget.selfId),
    ...widget.present.where((m) => m.userId != widget.selfId),
  ];

  @override
  void didUpdateWidget(FacecamRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = widget.present.map((m) => m.userId).toSet();
    for (final member in oldWidget.present) {
      if (now.contains(member.userId) || _leaving.containsKey(member.userId)) {
        continue;
      }
      _leaving[member.userId] = member;
      _leavingTimers[member.userId] = Timer(PTMotion.state, () {
        _leavingTimers.remove(member.userId);
        if (mounted) setState(() => _leaving.remove(member.userId));
      });
    }
    // A member who reappears mid-fade takes their real slot straight back.
    for (final id in now) {
      _leavingTimers.remove(id)?.cancel();
      _leaving.remove(id);
    }
  }

  @override
  void dispose() {
    for (final timer in _leavingTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.av,
      builder: (context, _) {
        final ordered = _ordered;
        final visible = ordered.take(widget.maxTiles).toList();
        final overflow = ordered.length - visible.length;
        // Leavers only fill slots the live roster isn't using.
        final departing = _leaving.values
            .take((widget.maxTiles - visible.length).clamp(0, widget.maxTiles))
            .toList();

        final tiles = <Widget>[
          for (final member in [...visible, ...departing])
            _AnimatedTile(
              key: ValueKey(member.userId),
              leaving: _leaving.containsKey(member.userId),
              child: _FacecamTile(
                member: member,
                isSelf: member.userId == widget.selfId,
                premium: widget.premiumMembers.contains(member.userId),
                av: widget.av,
                compact: widget.layout != .railLeft,
                showNames: widget.showNames,
              ),
            ),
          if (overflow > 0 && widget.layout == .miniStackRight)
            PTActionPill(label: '+$overflow', icon: Symbols.sync_rounded),
          if (widget.onHide != null && widget.layout == .railLeft)
            PTActionPill(
              label: 'Hide cams',
              icon: Symbols.keyboard_arrow_left_rounded,
              onTap: widget.onHide,
            ),
        ];

        final rail = switch (widget.layout) {
          .railLeft => SizedBox(
            width: 200,
            child: Column(crossAxisAlignment: .start, spacing: 10, children: tiles),
          ),
          .stripTop => Row(spacing: 8, children: [for (final t in tiles) Expanded(child: t)]),
          .miniStackRight => Column(crossAxisAlignment: .end, spacing: 6, children: tiles),
        };

        return AnimatedSize(
          duration: PTMotion.functional(context, PTMotion.state),
          curve: PTMotion.enter,
          alignment: widget.layout == .miniStackRight ? .topRight : .topLeft,
          child: rail,
        );
      },
    );
  }
}

class _AnimatedTile extends StatelessWidget {
  const _AnimatedTile({super.key, required this.child, required this.leaving});

  final Widget child;
  final bool leaving;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: leaving ? 0.95 : 1,
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.exit,
      child: AnimatedOpacity(
        opacity: leaving ? 0 : 1,
        duration: PTMotion.functional(context, PTMotion.state),
        child: PTEntrance(duration: PTMotion.state, offset: 0, scaleFrom: 0.95, child: child),
      ),
    );
  }
}

class _FacecamTile extends StatelessWidget {
  const _FacecamTile({
    required this.member,
    required this.isSelf,
    required this.premium,
    required this.av,
    required this.compact,
    required this.showNames,
  });

  final PresentMember member;
  final bool isSelf;
  final bool premium;
  final LiveKitService av;
  final bool compact;
  final bool showNames;

  lk.Participant? get _participant {
    if (isSelf) return av.localParticipant;
    for (final p in av.remoteParticipants) {
      if (p.identity == member.userId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final participant = _participant;
    final videoTrack = _videoTrack(participant);
    final micOff = _micOff(participant);
    final speaking = participant?.isSpeaking ?? false;

    final height = compact ? 58.0 : 112.0;
    final radius = compact ? 13.0 : 16.0;

    // The highest-value AV micro: this is how you know who just laughed.
    // Snaps on and lingers on the way out, the way a voice does — an equal
    // fade both ways reads as a flicker on short utterances.
    return AnimatedContainer(
      duration: speaking ? const Duration(milliseconds: 200) : const Duration(milliseconds: 600),
      curve: PTMotion.enter,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: speaking
              ? const Color(0xFFC4A8FF)
              : isSelf
              ? const Color(0xFFC4A8FF).withValues(alpha: 0.85)
              : PTColors.white(0.13),
          width: speaking || isSelf ? 2 : 1,
        ),
        boxShadow: [
          if (speaking)
            BoxShadow(
              color: PTColors.primary.withValues(alpha: 0.55),
              blurRadius: 16,
              spreadRadius: 2,
            )
          else if (isSelf)
            BoxShadow(color: PTColors.primary.withValues(alpha: 0.25), spreadRadius: 3),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          fit: .expand,
          children: [
            if (videoTrack != null)
              lk.VideoTrackRenderer(videoTrack, fit: .cover)
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: .topLeft,
                    end: .bottomRight,
                    colors: [Color(0xFF1F1A33), Color(0xFF151021)],
                  ),
                ),
                child: Center(
                  child: compact
                      ? PTAvatar(
                          userId: member.userId,
                          displayName: member.displayName,
                          size: 24,
                          premium: premium,
                        )
                      : Column(
                          mainAxisSize: .min,
                          spacing: 7,
                          children: [
                            PTAvatar(
                              userId: member.userId,
                              displayName: member.displayName,
                              size: 40,
                              premium: premium,
                            ),
                            Row(
                              mainAxisSize: .min,
                              spacing: 5,
                              children: [
                                AnimatedSize(
                                  duration: PTMotion.functional(context, PTMotion.state),
                                  curve: showNames ? PTMotion.enter : PTMotion.exit,
                                  child: showNames
                                      ? Text(
                                          member.displayName,
                                          style: PTText.finePrint.copyWith(
                                            fontSize: 11,
                                            color: PTColors.white(0.6),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                Icon(
                                  member.privacyMode
                                      ? Symbols.visibility_off_rounded
                                      : Symbols.videocam_off_rounded,
                                  size: 12,
                                  fill: 1,
                                  color: PTColors.white(0.4),
                                ),
                              ],
                            ),
                            if (member.privacyMode)
                              Text(
                                'Screen hidden',
                                style: PTText.finePrint.copyWith(
                                  fontSize: 10,
                                  color: PTColors.white(0.42),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            if (videoTrack != null || compact)
              Positioned(
                left: compact ? 5 : 8,
                bottom: compact ? 5 : 8,
                child: AnimatedSlide(
                  offset: showNames ? Offset.zero : const Offset(0, 0.5),
                  duration: PTMotion.functional(context, PTMotion.state),
                  curve: showNames ? PTMotion.enter : PTMotion.exit,
                  child: AnimatedOpacity(
                    opacity: showNames ? 1 : 0,
                    duration: PTMotion.functional(context, PTMotion.state),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 7 : 9,
                        vertical: compact ? 2 : 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x9908070C),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: .min,
                        spacing: 3,
                        children: [
                          Text(
                            isSelf ? 'You' : member.displayName,
                            overflow: .ellipsis,
                            style: TextStyle(
                              fontFamily: PTFonts.body,
                              fontSize: compact ? 9.5 : 11,
                              fontWeight: isSelf ? .w600 : .w500,
                              color: Colors.white,
                            ),
                          ),
                          if (member.privacyMode)
                            Icon(
                              Symbols.visibility_off_rounded,
                              size: compact ? 10 : 12,
                              fill: 1,
                              color: PTColors.white(0.75),
                            ),
                          // The border glow is now the primary speaking cue; this
                          // stays as a redundant, colour-blind-safe marker.
                          AnimatedSize(
                            duration: PTMotion.functional(context, PTMotion.state),
                            curve: PTMotion.enter,
                            child: speaking
                                ? Icon(
                                    Symbols.graphic_eq_rounded,
                                    size: compact ? 10 : 12,
                                    color: PTColors.textAccent,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: compact ? 5 : 7,
              right: compact ? 5 : 7,
              child: AnimatedScale(
                scale: micOff && participant != null ? 1 : 0,
                duration: PTMotion.functional(context, PTMotion.state),
                curve: micOff ? PTMotion.arrive : PTMotion.exit,
                child: Container(
                  width: compact ? 17 : 22,
                  height: compact ? 17 : 22,
                  decoration: BoxDecoration(
                    color: const Color(0xD92A1414),
                    shape: .circle,
                    border: Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.45)),
                  ),
                  child: Icon(
                    Symbols.mic_off_rounded,
                    size: compact ? 10 : 12,
                    fill: 1,
                    color: PTColors.danger,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _micOff(lk.Participant? participant) {
    if (participant == null) return true;
    final pubs = participant.audioTrackPublications;
    return pubs.isEmpty || pubs.every((pub) => pub.muted);
  }

  lk.VideoTrack? _videoTrack(lk.Participant? participant) {
    if (participant == null) return null;
    for (final publication in participant.videoTrackPublications) {
      if (publication.subscribed && !publication.muted && publication.track != null) {
        return publication.track as lk.VideoTrack;
      }
    }
    return null;
  }
}
