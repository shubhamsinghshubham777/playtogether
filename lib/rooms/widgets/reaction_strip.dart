import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:playtogether/rooms/reactions.dart';
import 'package:playtogether/rooms/widgets/reaction_overlay.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';

class ReactionStrip extends StatefulWidget {
  const ReactionStrip({
    super.key,
    required this.open,
    required this.assets,
    required this.onPick,
    this.compact = false,
  });

  final bool open;
  final ReactionAssets assets;
  final ValueChanged<PTReaction> onPick;
  final bool compact;

  @override
  State<ReactionStrip> createState() => _ReactionStripState();
}

class _ReactionStripState extends State<ReactionStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: PTMotion.panel,
    reverseDuration: PTMotion.panel,
    value: widget.open ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.open) _ensureAssets();
  }

  void _ensureAssets() {
    widget.assets.preload().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ReactionStrip old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      _ensureAssets();
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final size = compact ? 34.0 : 42.0;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _anim.value;
        if (t == 0) return const SizedBox.shrink();
        final closing = _anim.status == AnimationStatus.reverse;
        final eased = closing ? PTMotion.emphasized.transform(t) : PTMotion.arrive.transform(t);
        final slot = Align(
          alignment: .bottomCenter,
          heightFactor: (closing ? eased : t).clamp(0.0, 1.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Transform.translate(
              offset: Offset(0, (1 - eased) * 22),
              child: Transform.scale(
                scale: 0.88 + 0.12 * eased,
                alignment: .bottomCenter,
                child: IgnorePointer(ignoring: closing, child: child),
              ),
            ),
          ),
        );
        return closing ? ClipRect(child: slot) : slot;
      },
      child: Center(
        child: GlassPill(
          opacity: 0.62,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 6 : 7),
          child: FittedBox(
            fit: .scaleDown,
            child: Row(
              mainAxisSize: .min,
              spacing: compact ? 2 : 4,
              children: [
                for (final reaction in kReactions)
                  _ReactionCell(
                    reaction: reaction,
                    composition: widget.assets.of(reaction),
                    size: size,
                    onTap: () => widget.onPick(reaction),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionCell extends StatefulWidget {
  const _ReactionCell({
    required this.reaction,
    required this.composition,
    required this.size,
    required this.onTap,
  });

  final PTReaction reaction;
  final LottieComposition? composition;
  final double size;
  final VoidCallback onTap;

  @override
  State<_ReactionCell> createState() => _ReactionCellState();
}

class _ReactionCellState extends State<_ReactionCell> with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(vsync: this);
  bool _hovered = false;

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  void _preview() {
    final composition = widget.composition;
    if (composition == null || reducedMotion(context)) return;
    _play.duration = composition.duration;
    _play.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final composition = widget.composition;
    final padded = widget.size + (widget.size < 40 ? 8 : 10);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        _preview();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.reaction.label,
        waitDuration: const Duration(milliseconds: 400),
        child: PTPressable(
          onTap: () {
            _preview();
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: PTMotion.hover,
            curve: PTMotion.enter,
            width: padded,
            height: padded,
            decoration: BoxDecoration(
              color: _hovered ? PTColors.white(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(padded / 2),
            ),
            child: Center(
              child: SizedBox.square(
                dimension: widget.size,
                child: composition == null
                    ? Center(
                        child: Text(
                          widget.reaction.emoji,
                          style: TextStyle(fontSize: widget.size * 0.78),
                        ),
                      )
                    : AnimatedBuilder(
                        animation: _play,
                        builder: (context, _) => RawLottie(
                          composition: composition,
                          progress: _play.value,
                          fit: .contain,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
