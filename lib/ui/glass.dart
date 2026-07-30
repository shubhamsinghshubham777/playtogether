import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'pt_motion.dart';
import 'pt_theme.dart';

/// Glass recipe: bg rgba(22,18,38,.5–.6) · blur(28–32) saturate(160%) ·
/// border 1px white @ .13 · radius 20–28 · shadow 0 20 56 @ .5.
/// Never stack glass on glass more than two deep.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 22,
    this.opacity = 0.55,
    this.blur = 28,
    this.baseColor,
    this.borderColor,
    this.padding,
    this.shadow = true,
    this.clipBehavior = Clip.antiAlias,
  });

  /// Dialog-grade glass (denser, over a scrim).
  const GlassPanel.dialog({
    super.key,
    required this.child,
    this.radius = 24,
    this.opacity = 0.78,
    this.blur = 32,
    this.baseColor = PTColors.dialogGlassBase,
    this.borderColor,
    this.padding,
    this.shadow = true,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final double radius;
  final double opacity;
  final double blur;
  final Color? baseColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 56,
                  offset: const Offset(0, 20),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
            inner: const ColorFilter.matrix(_saturation160),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (baseColor ?? PTColors.glassBase).withValues(alpha: opacity),
              borderRadius: borderRadius,
              border: Border.all(color: borderColor ?? PTColors.white(0.13)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// saturate(160%) as a color matrix (Rec. 709 luma weights).
const _saturation160 = <double>[
  0.8726, 0.4290, 0.0983, 0, 0, //
  0.1274, 1.1741, 0.0983, 0, 0, //
  0.1274, 0.4290, 1.4434, 0, 0, //
  0, 0, 0, 1, 0,
];

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    this.onTap,
    this.opacity = 0.55,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final pill = GlassPanel(
      radius: 999,
      opacity: opacity,
      blur: 24,
      padding: padding,
      child: child,
    );
    if (onTap == null) return pill;
    // Scale, never fade: PTPressable animates a Transform, which leaves the
    // pill's BackdropFilter sampling a real backdrop.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PTPressable(onTap: onTap, child: pill),
    );
  }
}

/// Ambient violet glow blobs behind empty screens (Login, Lobby, Profile).
/// Never used in the room — nothing ambient may move near playing video.
///
/// The blobs drift along phase-offset elliptical paths with coprime-ish rates
/// so they never visibly sync up. **Translation only, no scale**: these are
/// 640–720 px circles under a sigma-45+ blur, and a per-frame scale would
/// invalidate the raster cache and re-blur them every frame. A pure
/// `Transform.translate` moves the cached layer instead.
///
/// The drift **ping-pongs** (`repeat(reverse: true)`) rather than wrapping: those
/// coprime rates — and the `cos(t * 0.6)` on the vertical axis — leave the trig
/// phase mid-cycle when the controller reaches 1, so a plain `repeat()` snapped
/// all three layers back to frame 0 every period. `easeInOut` is the other half
/// of the fix; its zero velocity at both ends makes the turnaround a stall
/// rather than a bounce.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  // One controller for all three; TickerMode pauses it for free while the
  // route is offstage, so the lobby stops animating behind an open room.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: PTMotion.ambient,
  )..repeat(reverse: true);

  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _drift,
    curve: Curves.easeInOut,
    reverseCurve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _eased.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);
    return DecoratedBox(
      decoration: const BoxDecoration(color: PTColors.screenBg),
      child: Stack(
        fit: .expand,
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -180,
            left: -120,
            child: _drifting(
              0,
              44,
              30,
              1.0,
              still,
              const _GlowBlob(size: 640, color: Color(0x387C3AED), blur: 110),
            ),
          ),
          Positioned(
            bottom: -220,
            right: -100,
            child: _drifting(
              0.37,
              38,
              34,
              0.78,
              still,
              const _GlowBlob(size: 720, color: Color(0x24C084FC), blur: 120),
            ),
          ),
          Positioned(
            top: 270,
            right: 300,
            child: _drifting(
              0.71,
              30,
              26,
              1.31,
              still,
              const _GlowBlob(size: 280, color: Color(0x296366F1), blur: 90),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }

  Widget _drifting(double phase, double ampX, double ampY, double rate, bool still, Widget blob) {
    if (still) return blob;
    return AnimatedBuilder(
      animation: _eased,
      child: RepaintBoundary(child: blob),
      builder: (context, child) {
        final t = (_eased.value * rate + phase) * 2 * math.pi;
        return Transform.translate(
          offset: Offset(math.sin(t) * ampX, math.cos(t * 0.6) * ampY),
          child: child,
        );
      },
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color, required this.blur});

  final double size;
  final Color color;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: .circle, color: color),
      ),
    );
  }
}

/// Shows a dialog with the standard dark scrim + blur, glass shell provided by
/// [GlassPanel.dialog]. All redesigned dialogs go through this.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  double width = 430,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'dialog',
    barrierColor: const Color(0x8C06050A),
    transitionDuration: PTMotion.panel,
    pageBuilder: (context, _, _) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Material(
            type: .transparency,
            child: GlassPanel.dialog(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 30),
              child: builder(context),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: PTMotion.enter,
        reverseCurve: PTMotion.exit,
      );
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6 * animation.value, sigmaY: 6 * animation.value),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        ),
      );
    },
  );
}
