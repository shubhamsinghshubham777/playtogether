import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final double size;

  /// null = no dot; true = online (green); false = away (grey).
  final bool? presence;
  final Color? ringColor;

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

    if (presence != null) {
      final dot = size * 0.29;
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: presence! ? PTColors.online : PTColors.away,
                shape: .circle,
                border: Border.all(color: PTColors.presenceRing, width: 2),
              ),
            ),
          ),
        ],
      );
    }
    return avatar;
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
class RoomCodeChip extends StatelessWidget {
  const RoomCodeChip({super.key, required this.code, this.onCopy, this.fontSize = 13});

  final String code;
  final VoidCallback? onCopy;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onCopy != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onCopy,
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
                code,
                style: TextStyle(
                  fontFamily: PTFonts.mono,
                  fontSize: fontSize,
                  fontWeight: .w500,
                  letterSpacing: fontSize * 0.18,
                  color: PTColors.textAccent,
                ),
              ),
              if (onCopy != null)
                Icon(
                  Symbols.content_copy_rounded,
                  size: fontSize + 2,
                  fill: 1,
                  color: PTColors.textAccent,
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
            style: TextStyle(
              fontFamily: PTFonts.body,
              fontSize: 12,
              color: PTColors.white(0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unread-count bubble anchored to a corner of its child.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 19),
            height: 19,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: const BoxDecoration(
              color: PTColors.primary,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
            alignment: .center,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                fontFamily: PTFonts.body,
                fontSize: 11,
                fontWeight: .w600,
                color: Colors.white,
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
  late final _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

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
