import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'pt_motion.dart';
import 'pt_theme.dart';

enum PTButtonVariant { primary, secondary, destructive }

class PTButton extends StatefulWidget {
  const PTButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = PTButtonVariant.primary,
    this.icon,
    this.trailingIcon,
    this.height = 50,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PTButtonVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;
  final double height;
  final bool expand;
  final bool loading;

  @override
  State<PTButton> createState() => _PTButtonState();
}

class _PTButtonState extends State<PTButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;

    final (
      Gradient? gradient,
      Color? color,
      Border? border,
      Color foreground,
    ) = switch (widget.variant) {
      PTButtonVariant.primary => (PTColors.buttonGradient, null, null, Colors.white),
      PTButtonVariant.secondary => (
        null,
        PTColors.white(_hovered ? 0.12 : 0.07),
        Border.all(color: PTColors.white(0.14)),
        Colors.white,
      ),
      PTButtonVariant.destructive => (
        null,
        _hovered ? PTColors.dangerBorder.withValues(alpha: 0.1) : Colors.transparent,
        Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.3)),
        PTColors.danger,
      ),
    };

    final label = Text(
      widget.label,
      // The button is a fixed height, so a label that wraps gets clipped
      // rather than growing the button. Degrade to an ellipsis instead.
      maxLines: 1,
      overflow: .ellipsis,
      textAlign: .center,
      style: PTText.buttonLabel.copyWith(
        color: foreground,
        fontWeight: widget.variant == .primary ? .w600 : .w500,
      ),
    );

    final content = AnimatedSwitcher(
      duration: PTMotion.functional(context, PTMotion.state),
      switchInCurve: PTMotion.enter,
      switchOutCurve: PTMotion.exit,
      child: widget.loading
          ? SizedBox.square(
              key: const ValueKey('loading'),
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: foreground),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              spacing: 10,
              children: [
                if (widget.icon != null) Icon(widget.icon, size: 19, color: foreground),
                Flexible(child: label),
                if (widget.trailingIcon != null)
                  Icon(widget.trailingIcon, size: 19, color: foreground),
              ],
            ),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        enabled: enabled,
        onTap: widget.onPressed,
        child: AnimatedOpacity(
          duration: Durations.short2,
          opacity: enabled || widget.loading ? 1 : 0.45,
          child: Container(
            height: widget.height,
            width: widget.expand ? double.infinity : null,
            padding: widget.expand ? null : const EdgeInsets.symmetric(horizontal: 22),
            alignment: .center,
            decoration: BoxDecoration(
              gradient: gradient,
              color: color,
              border: border,
              borderRadius: BorderRadius.circular(16),
              boxShadow: widget.variant == .primary && enabled
                  ? [
                      BoxShadow(
                        color: PTColors.primary.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            foregroundDecoration: widget.variant == .primary && _hovered && enabled
                ? BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  )
                : null,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 44px round glass icon button (min touch target per design rules).
class PTIconButton extends StatefulWidget {
  const PTIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 21,
    this.tooltip,
    this.active = false,
    this.glass = true,
    this.color,
    this.borderRadius,
    this.spinOnPress = 0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;

  /// Active = violet fill (e.g. chat open, mic on).
  final bool active;

  /// When false, renders borderless (bare icon on a hover circle).
  final bool glass;
  final Color? color;
  final BorderRadius? borderRadius;

  /// Degrees the glyph swings and springs back on tap — signed, so the ∓10 s
  /// skip buttons confirm their direction the way the flash badge does.
  final double spinOnPress;

  @override
  State<PTIconButton> createState() => _PTIconButtonState();
}

class _PTIconButtonState extends State<PTIconButton> with SingleTickerProviderStateMixin {
  bool _hovered = false;

  AnimationController? _spinController;

  AnimationController get _spin =>
      _spinController ??= AnimationController(vsync: this, duration: PTMotion.state);

  @override
  void dispose() {
    _spinController?.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.spinOnPress != 0 && !reducedMotion(context)) _spin.forward(from: 0);
    widget.onPressed!.call();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(999);

    final decoration = widget.active
        ? BoxDecoration(
            color: PTColors.primary.withValues(alpha: 0.45),
            border: Border.all(color: const Color(0xFFC4A8FF).withValues(alpha: 0.5)),
            borderRadius: radius,
          )
        : widget.glass
        ? BoxDecoration(
            color: _hovered ? PTColors.white(0.12) : PTColors.glass(0.55),
            border: Border.all(color: PTColors.white(0.13)),
            borderRadius: radius,
          )
        : BoxDecoration(
            color: _hovered ? PTColors.white(0.1) : Colors.transparent,
            borderRadius: radius,
          );

    final iconColor =
        widget.color ?? (widget.active ? const Color(0xFFE9DCFF) : PTColors.white(0.85));
    // Keyed by glyph so every icon swap in the kit — volume_up ⇄ volume_off,
    // mic on/off, chat open/closed — cross-fades instead of snapping.
    Widget glyph = AnimatedSwitcher(
      duration: PTMotion.functional(context, PTMotion.hover),
      child: Icon(widget.icon, key: ValueKey(widget.icon), size: widget.iconSize, color: iconColor),
    );

    if (widget.spinOnPress != 0) {
      final radians = widget.spinOnPress * math.pi / 180;
      glyph = AnimatedBuilder(
        animation: _spin,
        child: glyph,
        // Out and back within the one controller: sin() peaks at the midpoint
        // and lands exactly on zero, so the glyph never rests off-axis.
        builder: (context, child) =>
            Transform.rotate(angle: radians * math.sin(_spin.value * math.pi), child: child),
      );
    }

    Widget button = MouseRegion(
      cursor: widget.onPressed != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        onTap: widget.onPressed == null ? null : _handleTap,
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          width: widget.size,
          height: widget.size,
          decoration: decoration,
          child: glyph,
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// The 58px gradient play/pause button.
class PTPlayButton extends StatelessWidget {
  const PTPlayButton({super.key, required this.playing, required this.onPressed, this.size = 58});

  final bool playing;

  /// Null disables the button (dimmed, no cursor), matching [PTButton].
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: PTPressable(
        enabled: enabled,
        onTap: onPressed,
        pressedScale: 0.93,
        child: AnimatedOpacity(
          duration: PTMotion.functional(context, PTMotion.hover),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: PTColors.buttonGradient,
              shape: .circle,
              boxShadow: [
                BoxShadow(
                  color: PTColors.primary.withValues(alpha: 0.5),
                  blurRadius: 26,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            // Cross-faded rather than an AnimatedIcon: AnimatedIcons.play_pause
            // draws Material's *sharp* glyphs, which read as a foreign icon set
            // next to the rounded family this app uses everywhere else.
            child: AnimatedSwitcher(
              duration: PTMotion.functional(context, PTMotion.state),
              switchInCurve: PTMotion.enter,
              switchOutCurve: PTMotion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.75, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                size: size * 0.55,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Google sign-in button: white pill w/ the multicolor G mark.
class GoogleButton extends StatefulWidget {
  const GoogleButton({super.key, required this.label, this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  State<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<GoogleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        enabled: enabled,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          height: 52,
          alignment: .center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered && enabled ? 1 : 0.92),
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedSwitcher(
            duration: PTMotion.functional(context, PTMotion.state),
            switchInCurve: PTMotion.enter,
            switchOutCurve: PTMotion.exit,
            child: widget.loading
                ? const SizedBox.square(
                    key: ValueKey('loading'),
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF1A1625)),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisSize: .min,
                    spacing: 12,
                    children: [
                      const _GoogleMark(),
                      Text(
                        widget.label,
                        style: PTText.buttonLabel.copyWith(color: const Color(0xFF1A1625)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(dimension: 20, child: CustomPaint(painter: _GoogleMarkPainter()));
  }
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    final paint = Paint()..style = .fill;

    Path scaled(Path p) => p.transform(Matrix4.diagonal3Values(s, s, 1).storage);

    paint.color = const Color(0xFFEA4335);
    canvas.drawPath(
      scaled(
        Path()
          ..moveTo(24, 9.5)
          ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
          ..lineTo(40.06, 6.25)
          ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
          ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
          ..lineTo(10.54, 19.41)
          ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
          ..close(),
      ),
      paint,
    );
    paint.color = const Color(0xFF4285F4);
    canvas.drawPath(
      scaled(
        Path()
          ..moveTo(46.98, 24.55)
          ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
          ..lineTo(24, 20)
          ..lineTo(24, 29.02)
          ..lineTo(36.94, 29.02)
          ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
          ..lineTo(39.89, 42.2)
          ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
          ..close(),
      ),
      paint,
    );
    paint.color = const Color(0xFFFBBC05);
    canvas.drawPath(
      scaled(
        Path()
          ..moveTo(10.53, 28.59)
          ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
          ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
          ..lineTo(2.55, 13.22)
          ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
          ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
          ..lineTo(10.53, 28.59)
          ..close(),
      ),
      paint,
    );
    paint.color = const Color(0xFF34A853);
    canvas.drawPath(
      scaled(
        Path()
          ..moveTo(24, 48)
          ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
          ..lineTo(32.16, 36.19)
          ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
          ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
          ..lineTo(2.55, 34.77)
          ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
          ..close(),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small glass action pill with label + optional icon ("Hide cams", "+1 …").
class PTActionPill extends StatelessWidget {
  const PTActionPill({super.key, required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          if (icon != null) Icon(icon, size: 15, color: PTColors.white(0.65)),
          Text(label, style: PTText.finePrint.copyWith(fontSize: 12, color: PTColors.white(0.65))),
        ],
      ),
    );
  }
}
