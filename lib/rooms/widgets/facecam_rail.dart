import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/av/livekit_service.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/pt_theme.dart';

enum FacecamLayout { railLeft, stripTop, miniStackRight }

/// Facecam tiles per present member: live video when the member publishes a
/// cam track, avatar tile otherwise; self first with the violet ring.
class FacecamRail extends StatelessWidget {
  const FacecamRail({
    super.key,
    required this.av,
    required this.present,
    required this.selfId,
    required this.layout,
    this.onHide,
    this.maxTiles = 4,
  });

  final LiveKitService av;
  final List<PresentMember> present;
  final String selfId;
  final FacecamLayout layout;
  final VoidCallback? onHide;
  final int maxTiles;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: av,
      builder: (context, _) {
        final ordered = [
          ...present.where((m) => m.userId == selfId),
          ...present.where((m) => m.userId != selfId),
        ];
        final visible = ordered.take(maxTiles).toList();
        final overflow = ordered.length - visible.length;

        final tiles = <Widget>[
          for (final member in visible)
            _FacecamTile(
              member: member,
              isSelf: member.userId == selfId,
              av: av,
              compact: layout != .railLeft,
            ),
          if (overflow > 0 && layout == .miniStackRight)
            PTActionPill(label: '+$overflow', icon: Symbols.sync_rounded),
          if (onHide != null && layout == .railLeft)
            PTActionPill(
              label: 'Hide cams',
              icon: Symbols.keyboard_arrow_left_rounded,
              onTap: onHide,
            ),
        ];

        return switch (layout) {
          .railLeft => SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: .start,
              spacing: 10,
              children: tiles,
            ),
          ),
          .stripTop => Row(
            spacing: 8,
            children: [for (final t in tiles) Expanded(child: t)],
          ),
          .miniStackRight => Column(
            crossAxisAlignment: .end,
            spacing: 6,
            children: tiles,
          ),
        };
      },
    );
  }
}

class _FacecamTile extends StatelessWidget {
  const _FacecamTile({
    required this.member,
    required this.isSelf,
    required this.av,
    required this.compact,
  });

  final PresentMember member;
  final bool isSelf;
  final LiveKitService av;
  final bool compact;

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

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: isSelf
            ? Border.all(color: const Color(0xFFC4A8FF).withValues(alpha: 0.85), width: 2)
            : Border.all(color: PTColors.white(0.13)),
        boxShadow: [
          if (isSelf) BoxShadow(color: PTColors.primary.withValues(alpha: 0.25), spreadRadius: 3),
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
              lk.VideoTrackRenderer(videoTrack)
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
                      ? PTAvatar(userId: member.userId, displayName: member.displayName, size: 24)
                      : Column(
                          mainAxisSize: .min,
                          spacing: 7,
                          children: [
                            PTAvatar(
                              userId: member.userId,
                              displayName: member.displayName,
                              size: 40,
                            ),
                            Row(
                              mainAxisSize: .min,
                              spacing: 5,
                              children: [
                                Text(
                                  member.displayName,
                                  style: PTText.finePrint.copyWith(
                                    fontSize: 11,
                                    color: PTColors.white(0.6),
                                  ),
                                ),
                                Icon(
                                  Symbols.videocam_off_rounded,
                                  size: 12,
                                  fill: 1,
                                  color: PTColors.white(0.4),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            if (videoTrack != null || compact)
              Positioned(
                left: compact ? 5 : 8,
                bottom: compact ? 5 : 8,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 2 : 3),
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
                      if (speaking)
                        Icon(
                          Symbols.graphic_eq_rounded,
                          size: compact ? 10 : 12,
                          color: PTColors.textAccent,
                        ),
                    ],
                  ),
                ),
              ),
            if (micOff && participant != null)
              Positioned(
                top: compact ? 5 : 7,
                right: compact ? 5 : 7,
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
