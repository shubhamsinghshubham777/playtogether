import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';

/// What one member's readiness looks like in the roster.
class ReadinessChipStyle {
  const ReadinessChipStyle(this.label, this.color);

  final String label;
  final Color color;

  /// A member who is "ready" but holding the wrong file reads as a problem, not
  /// as progress — the gate treats them the same way.
  static ReadinessChipStyle of(PresentMember member, RoomMedia media) {
    if (media.kind == .local && member.isReady && member.loadedFileName != media.name) {
      return ReadinessChipStyle(
        'Wrong file · ${member.loadedFileName ?? 'nothing'}',
        PTColors.danger,
      );
    }
    return switch (member.readyStatus) {
      ReadyStatus.ready => const ReadinessChipStyle('Ready', PTColors.online),
      ReadyStatus.loading => const ReadinessChipStyle('Loading', PTColors.textAccent),
      ReadyStatus.selecting => const ReadinessChipStyle('Choosing…', PTColors.textAccent),
      ReadyStatus.none => ReadinessChipStyle('Not ready', PTColors.white(0.5)),
    };
  }
}

/// Covers the video surface while the readiness gate is shut. Scoped to the
/// video only, on purpose (D2): chat, facecams and the member list stay
/// usable while the room waits.
///
/// [reveal] drives the whole in/out animation, 0 → 1. The glass is faded by
/// tweening `GlassPanel`'s own `opacity`/`blur` arguments rather than by any
/// enclosing `Opacity`: an opacity layer around a `BackdropFilter` leaves it
/// sampling an empty layer, so the panel would go flat exactly while it is
/// most visible. The scrim is a plain colour and animates freely.
class ReadinessOverlay extends StatelessWidget {
  const ReadinessOverlay({
    super.key,
    required this.headline,
    required this.members,
    required this.media,
    required this.selfId,
    required this.selfIsHost,
    required this.onLocateFile,
    required this.onKick,
    this.onStartWithout,
    this.startWithoutLabel,
    this.compact = false,
    this.reveal = 1,
    this.premiumMembers = const {},
    this.uploadProgressWidget,
  });

  final String headline;
  final List<PresentMember> members;
  final RoomMedia media;
  final String selfId;
  final bool selfIsHost;
  final Widget? uploadProgressWidget;

  /// Null unless *we* are the one who needs to find their copy.
  final VoidCallback? onLocateFile;
  final void Function(PresentMember member)? onKick;

  final VoidCallback? onStartWithout;
  final String? startWithoutLabel;
  final bool compact;
  final double reveal;
  final Set<String> premiumMembers;

  @override
  Widget build(BuildContext context) {
    final t = reveal.clamp(0.0, 1.0);
    var row = 0;
    return Container(
      color: const Color(0xFF0A0812).withValues(alpha: 0.7 * t),
      alignment: .center,
      padding: EdgeInsets.all(compact ? 16 : 28),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Transform.scale(
            scale: 0.96 + 0.04 * t,
            child: GlassPanel(
              radius: compact ? 20 : 24,
              opacity: 0.72 * t,
              // Never exactly zero: a zero-sigma ImageFilter.blur is degenerate.
              blur: 6 + 28 * t,
              baseColor: const Color(0xFF141022),
              borderColor: PTColors.white(0.14 * t),
              shadow: false,
              padding: EdgeInsets.all(compact ? 18 : 24),
              // Safe to fade: this sits *inside* the panel, above its
              // BackdropFilter, so no blur is sampling through it.
              child: Opacity(
                opacity: t,
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  spacing: compact ? 14 : 18,
                  children: [
                    Row(
                      crossAxisAlignment: .start,
                      spacing: 12,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Symbols.hourglass_top_rounded,
                            size: compact ? 19 : 22,
                            color: PTColors.textAccent,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            headline,
                            // Media names run long ("Movie.2005.1080p.BluRay…"), and
                            // at the headline size they turn the panel into a wall
                            // of bold text. Step down once past a sentence or so.
                            style: PTText.body.copyWith(
                              fontSize: headline.length > 90
                                  ? (compact ? 13 : 14)
                                  : (compact ? 14.5 : 16),
                              fontWeight: .w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (uploadProgressWidget != null) uploadProgressWidget!,
                    if (members.isNotEmpty)
                      Column(
                        mainAxisSize: .min,
                        children: [
                          for (final member in members)
                            // Watching friends' chips flip green one by one is the
                            // "we're all here" moment; stagger the roster so it
                            // assembles rather than appearing whole.
                            PTEntrance(
                              delay: Duration(milliseconds: 40 * row++),
                              offset: 8,
                              child: _MemberStatusRow(
                                member: member,
                                media: media,
                                premium: premiumMembers.contains(member.userId),
                                isSelf: member.userId == selfId,
                                compact: compact,
                                // Reserve the kick column on every row, not just the
                                // kickable ones, so the status chips share a left
                                // edge instead of jumping about per row.
                                reserveKickSlot: selfIsHost,
                                onKick: selfIsHost && member.userId != selfId && !member.isHost
                                    ? () => onKick?.call(member)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    if (onLocateFile != null)
                      PTButton(
                        // Just the action — the headline directly above already
                        // names the file, and release names are long enough to
                        // swamp the panel if repeated here.
                        label: 'Locate your copy',
                        icon: Symbols.folder_open_rounded,
                        expand: true,
                        onPressed: onLocateFile,
                      ),
                    if (onStartWithout != null)
                      PTButton(
                        label: startWithoutLabel ?? 'Start without them',
                        icon: Symbols.fast_forward_rounded,
                        variant: .secondary,
                        expand: true,
                        onPressed: onStartWithout,
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
}

class _MemberStatusRow extends StatelessWidget {
  const _MemberStatusRow({
    required this.member,
    required this.media,
    required this.premium,
    required this.isSelf,
    required this.compact,
    required this.reserveKickSlot,
    required this.onKick,
  });

  final PresentMember member;
  final RoomMedia media;
  final bool premium;
  final bool isSelf;
  final bool compact;
  final bool reserveKickSlot;
  final VoidCallback? onKick;

  static const _kickSlot = 32.0;

  @override
  Widget build(BuildContext context) {
    final status = ReadinessChipStyle.of(member, media);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 10,
        children: [
          PTAvatar(
            userId: member.userId,
            displayName: member.displayName,
            avatarUrl: member.avatarUrl,
            size: 30,
            premium: premium,
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: member.displayName,
                children: [
                  if (isSelf)
                    TextSpan(
                      text: ' (you)',
                      style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                    )
                  else if (member.privacyMode)
                    TextSpan(
                      text: ' · screen hidden',
                      style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                    ),
                ],
              ),
              overflow: .ellipsis,
              style: PTText.body.copyWith(fontSize: 13.5, fontWeight: .w500),
            ),
          ),
          // Fixed-width column, left-aligned: chips vary a lot in width
          // ("Ready" vs "Wrong file · …"), and letting them size themselves
          // made every row start its chip somewhere different.
          SizedBox(
            width: compact ? 128 : 156,
            child: Align(
              alignment: .centerLeft,
              child: _StatusChip(status: status),
            ),
          ),
          if (onKick != null)
            PTIconButton(
              icon: Symbols.person_remove_rounded,
              glass: false,
              size: _kickSlot,
              iconSize: 17,
              tooltip: 'Remove ${member.displayName}',
              onPressed: onKick,
            )
          else if (reserveKickSlot)
            const SizedBox(width: _kickSlot),
        ],
      ),
    );
  }
}

/// Loading → Ready → Wrong file, animated. The tint crossfades with
/// `AnimatedContainer` while the label swaps through an `AnimatedSwitcher`, so
/// a member going green reads as a change of state rather than a redraw.
/// The chip's width is fixed by its parent, so nothing reflows as labels swap.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReadinessChipStyle status;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: AnimatedSwitcher(
        duration: PTMotion.functional(context, PTMotion.state),
        switchInCurve: PTMotion.enter,
        switchOutCurve: PTMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          status.label,
          key: ValueKey(status.label),
          overflow: .ellipsis,
          style: PTText.finePrint.copyWith(color: status.color, fontWeight: .w500),
        ),
      ),
    );
  }
}
