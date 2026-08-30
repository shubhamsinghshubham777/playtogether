import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'pt_motion.dart';
import 'pt_theme.dart';

/// Gradient avatar with the per-user fixed gradient; falls back to the first
/// letter of the display name when there is no photo.
class PTAvatar extends StatelessWidget {
  const PTAvatar({
    super.key,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.size = 36,
    this.presence,
    this.ringColor,
    this.premium = false,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final double size;

  /// null = no dot; true = online (green); false = away (grey).
  final bool? presence;
  final Color? ringColor;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final letter = displayName.isEmpty ? '?' : displayName.characters.first.toUpperCase();

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: avatarUrl == null ? PTColors.avatarGradientFor(userId) : null,
        shape: .circle,
        border: ringColor != null ? Border.all(color: ringColor!, width: 2) : null,
        image: avatarUrl != null
            ? DecorationImage(image: NetworkImage(avatarUrl!), fit: .cover)
            : null,
      ),
      alignment: .center,
      child: avatarUrl == null
          ? Text(
              letter,
              style: TextStyle(
                fontFamily: PTFonts.body,
                fontSize: size * 0.38,
                fontWeight: .w600,
                color: Colors.white,
              ),
            )
          : null,
    );

    if (presence != null || premium) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          if (premium)
            Positioned(
              top: -size * 0.13,
              right: -size * 0.09,
              child: PremiumCrown(size: size),
            ),
          if (presence != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: _PresenceDot(online: presence!, size: size * 0.29),
            ),
        ],
      );
    }
    return avatar;
  }
}

class PremiumCrown extends StatelessWidget {
  const PremiumCrown({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Symbols.crown_rounded,
      size: size * 0.46,
      fill: 1,
      weight: 600,
      color: PTColors.premium,
      semanticLabel: 'Premium',
      shadows: const [Shadow(color: PTColors.canvas, blurRadius: 4)],
    );
  }
}

/// Presence dot with a one-shot ripple when someone comes online. Deliberately
/// *not* a continuous pulse — eight avatars breathing forever is noise, and it
/// would keep the vsync awake for the whole session.
class _PresenceDot extends StatefulWidget {
  const _PresenceDot({required this.online, required this.size});

  final bool online;
  final double size;

  @override
  State<_PresenceDot> createState() => _PresenceDotState();
}

class _PresenceDotState extends State<_PresenceDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didUpdateWidget(_PresenceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Transition only. Rippling on first mount would fire for every member at
    // once on room entry, which reads as a glitch rather than an arrival.
    if (widget.online && !oldWidget.online && !reducedMotion(context)) {
      _ripple.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = widget.size;
    return SizedBox.square(
      dimension: dot,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: .center,
        children: [
          AnimatedBuilder(
            animation: _ripple,
            builder: (context, _) {
              if (_ripple.isDismissed || _ripple.isCompleted) {
                return const SizedBox.shrink();
              }
              final t = _ripple.value;
              return Container(
                width: dot * (1 + t * 1.6),
                height: dot * (1 + t * 1.6),
                decoration: BoxDecoration(
                  shape: .circle,
                  border: Border.all(
                    color: PTColors.online.withValues(alpha: 0.55 * (1 - t)),
                    width: 1.5,
                  ),
                ),
              );
            },
          ),
          AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.state),
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: widget.online ? PTColors.online : PTColors.away,
              shape: .circle,
              border: Border.all(color: PTColors.presenceRing, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlapping avatar row with a "+N" overflow chip.
class PTAvatarStack extends StatelessWidget {
  const PTAvatarStack({super.key, required this.entries, this.size = 36, this.maxVisible = 3});

  final List<({String userId, String displayName, String? avatarUrl})> entries;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(maxVisible).toList();
    final overflow = entries.length - visible.length;
    return SizedBox(
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (size - 10),
              child: PTAvatar(
                userId: visible[i].userId,
                displayName: visible[i].displayName,
                avatarUrl: visible[i].avatarUrl,
                size: size,
                ringColor: PTColors.avatarRing,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (size - 10),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: PTColors.white(0.1),
                  shape: .circle,
                  border: Border.all(color: PTColors.avatarRing, width: 2),
                ),
                alignment: .center,
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    fontFamily: PTFonts.body,
                    fontSize: size * 0.33,
                    fontWeight: .w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Copyable room-code chip: violet tint, JetBrains Mono, copy glyph.
///
/// The glyph flips to a tick for a beat after a copy — feedback lands where the
/// eye already is, which a snackbar at the other end of the screen never does.
class RoomCodeChip extends StatefulWidget {
  const RoomCodeChip({super.key, required this.code, this.onCopy, this.fontSize = 13});

  final String code;
  final VoidCallback? onCopy;
  final double fontSize;

  @override
  State<RoomCodeChip> createState() => _RoomCodeChipState();
}

class _RoomCodeChipState extends State<RoomCodeChip> {
  bool _copied = false;
  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  void _copy() {
    widget.onCopy!.call();
    setState(() => _copied = true);
    _revert?.cancel();
    _revert = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.fontSize;
    return MouseRegion(
      cursor: widget.onCopy != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: PTPressable(
        onTap: widget.onCopy == null ? null : _copy,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFA78BFA).withValues(alpha: 0.14),
            border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: .min,
            spacing: 8,
            children: [
              Text(
                widget.code,
                style: TextStyle(
                  fontFamily: PTFonts.mono,
                  fontSize: fontSize,
                  fontWeight: .w500,
                  letterSpacing: fontSize * 0.18,
                  color: PTColors.textAccent,
                ),
              ),
              if (widget.onCopy != null)
                AnimatedSwitcher(
                  duration: PTMotion.functional(context, PTMotion.state),
                  switchInCurve: PTMotion.enter,
                  switchOutCurve: PTMotion.exit,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: Icon(
                    _copied ? Symbols.check_rounded : Symbols.content_copy_rounded,
                    key: ValueKey(_copied),
                    size: fontSize + 2,
                    fill: 1,
                    color: _copied ? PTColors.online : PTColors.textAccent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HostBadge extends StatelessWidget {
  const HostBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: PTColors.warningBorder.withValues(alpha: 0.14),
        border: Border.all(color: PTColors.warningBorder.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Host',
        style: TextStyle(
          fontFamily: PTFonts.body,
          fontSize: 11,
          fontWeight: .w600,
          color: PTColors.warning,
        ),
      ),
    );
  }
}

class GuestBadge extends StatelessWidget {
  const GuestBadge({super.key, this.label = 'Guest session'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: PTColors.white(0.06),
        border: Border.all(color: PTColors.white(0.12)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          Icon(Symbols.lock_rounded, size: 14, fill: 1, color: PTColors.white(0.55)),
          Text(
            label,
            style: TextStyle(fontFamily: PTFonts.body, fontSize: 12, color: PTColors.white(0.55)),
          ),
        ],
      ),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.label = 'Premium'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: PTColors.premium.withValues(alpha: 0.14),
        border: Border.all(color: PTColors.premiumBorder.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          const Icon(Symbols.crown_rounded, size: 14, fill: 1, color: PTColors.premium),
          Text(
            label,
            style: const TextStyle(
              fontFamily: PTFonts.body,
              fontSize: 12,
              fontWeight: .w600,
              color: PTColors.premium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Unread-count bubble anchored to a corner of its child. Pops in with the
/// arrival overshoot and pulses on every increment — the one place in the app
/// where a message you haven't read needs to interrupt you.
class UnreadBadge extends StatefulWidget {
  const UnreadBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  State<UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<UnreadBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );

  @override
  void didUpdateWidget(UnreadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a rise: clearing the count unmounts the badge, and a bump on the way
    // out would just be noise behind the opening chat panel.
    if (widget.count > oldWidget.count && oldWidget.count > 0 && !reducedMotion(context)) {
      _bump.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          top: -4,
          right: -4,
          child: AnimatedScale(
            scale: count <= 0 ? 0 : 1,
            duration: PTMotion.functional(context, PTMotion.state),
            curve: count <= 0 ? PTMotion.exit : PTMotion.arrive,
            child: ScaleTransition(
              scale: TweenSequence<double>([
                TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 1),
                TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 1),
              ]).animate(_bump),
              child: Container(
                constraints: const BoxConstraints(minWidth: 19),
                height: 19,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: const BoxDecoration(
                  color: PTColors.primary,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                alignment: .center,
                child: AnimatedSwitcher(
                  duration: PTMotion.functional(context, PTMotion.hover),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    key: ValueKey(count),
                    style: const TextStyle(
                      fontFamily: PTFonts.body,
                      fontSize: 11,
                      fontWeight: .w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Animated three-dot typing indicator.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.size = 4});

  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: .min,
          spacing: 3,
          children: [
            for (var i = 0; i < 3; i++)
              Opacity(
                opacity: 0.3 + 0.6 * ((1 + i / 3 - _controller.value) % 1),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: const BoxDecoration(color: Colors.white, shape: .circle),
                ),
              ),
          ],
        );
      },
    );
  }
}
