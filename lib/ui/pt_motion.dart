import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motion tokens — the app's whole timing/easing vocabulary. Mirrors
/// [PTColors]/[PTText]: screens pick a token, never an inline `Duration`.
///
/// Two rules the rest of the kit depends on:
/// * **Glass glides, it doesn't fade.** Anything wrapping a `GlassPanel` (i.e.
///   a `BackdropFilter`) in `Opacity`/`FadeTransition` makes the blur sample an
///   empty layer and the glass goes flat mid-animation. Slide, scale or clip
///   glass — or animate `GlassPanel`'s own `opacity`/`blur` arguments, which is
///   a real fade without an opacity layer.
/// * **Decorative motion checks [reducedMotion] and renders the end state;
///   functional motion shortens instead of disappearing.**
abstract final class PTMotion {
  /// Press feedback (scale/opacity on tap-down).
  static const tap = Duration(milliseconds: 90);

  /// Hover fills, chips, small fades.
  static const hover = Duration(milliseconds: 140);

  /// State swaps: icons, badges, chips, banners.
  static const state = Duration(milliseconds: 220);

  /// Panels, overlays, dialogs. Deliberately equal to the chat panel's
  /// existing `Durations.medium1` — that animation is the reference, so
  /// adopting the token must not retune it.
  static const panel = Duration(milliseconds: 250);

  /// Route transitions. Shorter than a stock Material page transition on
  /// purpose: room entry already waits on an async load, so the transition is
  /// pure added latency and must stay fade-dominant and brief.
  static const page = Duration(milliseconds: 280);

  /// Entrance choreography (logo, cards, roster rows).
  static const entrance = Duration(milliseconds: 380);

  /// Looped ambient drift — idle screens only, never the room.
  static const ambient = Duration(seconds: 14);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const emphasized = Curves.easeInOutCubic;

  /// The one overshoot curve, for "arrival" moments only (unread badge,
  /// everyone's-ready toast, code completion). Never bounce/elastic — it
  /// fights the glass aesthetic.
  static const arrive = Curves.easeOutBack;

  /// Functional motion under reduce-motion: shorter, never removed.
  static Duration functional(BuildContext context, Duration d) =>
      reducedMotion(context) ? d * 0.5 : d;
}

/// True when the platform asks for reduced motion (macOS/iOS "Reduce motion",
/// Android animator scale 0). Decorative animation must render its end state.
bool reducedMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// Fade + rise (+ optional scale) on mount, with a [delay] for staggering.
///
/// [fade] must be **false** when the child is a `GlassPanel` — see the class
/// note on [PTMotion]. Children *inside* a panel sit above its `BackdropFilter`
/// and may fade freely.
class PTEntrance extends StatefulWidget {
  const PTEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = PTMotion.entrance,
    this.offset = 12,
    this.scaleFrom = 1.0,
    this.fade = true,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Pixels the child rises through on the way in.
  final double offset;

  /// 1.0 disables the scale leg.
  final double scaleFrom;

  /// Whether to fade — never for glass surfaces.
  final bool fade;

  /// False renders the end state immediately (e.g. a stagger that has already
  /// been played once this session).
  final bool enabled;

  @override
  State<PTEntrance> createState() => _PTEntranceState();
}

class _PTEntranceState extends State<PTEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: PTMotion.enter);
  Timer? _delay;
  bool _started = false;

  // Started here rather than in initState: the reduced-motion decision needs an
  // inherited MediaQuery, which isn't available that early.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || reducedMotion(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delay = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        Widget result = child!;
        if (widget.scaleFrom != 1.0) {
          result = Transform.scale(
            scale: widget.scaleFrom + (1 - widget.scaleFrom) * t,
            child: result,
          );
        }
        if (widget.offset != 0) {
          result = Transform.translate(offset: Offset(0, (1 - t) * widget.offset), child: result);
        }
        return widget.fade ? Opacity(opacity: t.clamp(0.0, 1.0), child: result) : result;
      },
    );
  }
}

/// Scale-on-press wrapper. Owns the tap gesture, so the widget it wraps must
/// not carry its own `GestureDetector` — hover/cursor stay with the caller.
///
/// Press feedback was the single biggest "feels static" gap on touch: every
/// button in the kit had a hover state and nothing at all for a finger.
class PTPressable extends StatefulWidget {
  const PTPressable({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.pressedScale = 0.97,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// False keeps the child inert (no press, no tap) without changing layout.
  final bool enabled;
  final double pressedScale;
  final HitTestBehavior behavior;

  @override
  State<PTPressable> createState() => _PTPressableState();
}

class _PTPressableState extends State<PTPressable> {
  bool _pressed = false;

  bool get _live => widget.enabled && widget.onTap != null;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTap: _live ? widget.onTap : null,
      onTapDown: _live ? (_) => _set(true) : null,
      onTapUp: _live ? (_) => _set(false) : null,
      onTapCancel: _live ? () => _set(false) : null,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: PTMotion.tap,
        curve: PTMotion.enter,
        child: widget.child,
      ),
    );
  }
}

/// Looping opacity breath. Decorative — renders its end state under
/// reduce-motion, and fades, so never wrap glass in it.
class PTPulse extends StatefulWidget {
  const PTPulse({
    super.key,
    required this.child,
    this.period = const Duration(seconds: 1),
    this.low = 0.45,
    this.high = 1.0,
    this.enabled = true,
  });

  final Widget child;
  final Duration period;
  final double low;
  final double high;
  final bool enabled;

  @override
  State<PTPulse> createState() => _PTPulseState();
}

class _PTPulseState extends State<PTPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  void _sync() {
    final run = widget.enabled && !reducedMotion(context);
    if (run && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!run && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PTPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: widget.low,
        end: widget.high,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine)),
      child: widget.child,
    );
  }
}

/// Horizontal "nope" shake. Bump [trigger] to play it once.
class PTShake extends StatefulWidget {
  const PTShake({super.key, required this.trigger, required this.child, this.magnitude = 6});

  final int trigger;
  final Widget child;
  final double magnitude;

  @override
  State<PTShake> createState() => _PTShakeState();
}

class _PTShakeState extends State<PTShake> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void didUpdateWidget(PTShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && !reducedMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (!_controller.isAnimating) return child!;
        // Three oscillations, decaying so it settles rather than stops dead.
        final t = _controller.value;
        final dx = widget.magnitude * (1 - t) * math.sin(t * math.pi * 6);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}
