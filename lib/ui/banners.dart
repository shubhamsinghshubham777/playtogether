import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/diagnostics.dart';

import 'identity.dart';
import 'pt_motion.dart';
import 'pt_theme.dart';

enum PTBannerKind { warning, info, error }

enum PTSnackKind { info, success, error }

/// Transient toast. Same tinted-surface recipe as [PTBanner] and deliberately
/// **not** glass: `ScaffoldMessenger` wraps floating snack bars in a
/// `FadeTransition`, and a `BackdropFilter` inside one samples an empty layer.
///
/// Newest wins — the queue is cleared before every show. Without that, holding
/// a blocked key (Space against a shut readiness gate) stacked one four-second
/// toast per keypress and the app spent half a minute telling you the same thing.
///
/// [bottomInset] lifts the toast clear of whatever owns the bottom edge; in a
/// room that is the floating control bar.
///
/// Never throws. If there is no `ScaffoldMessenger` to show it in, the toast is
/// dropped and the failure — including the message that was lost — is reported
/// to the error console rather than passing silently.
void showPTSnack(
  BuildContext context,
  String message, {
  PTSnackKind kind = PTSnackKind.info,
  double bottomInset = 0,
}) => showPTSnackVia(
  ScaffoldMessenger.maybeOf(context),
  message,
  kind: kind,
  bottomInset: bottomInset,
);

/// For callers holding a messenger key rather than a subtree context — the
/// deep-link handler in `main.dart` runs outside any screen.
void showPTSnackVia(
  ScaffoldMessengerState? messenger,
  String message, {
  PTSnackKind kind = PTSnackKind.info,
  double bottomInset = 0,
}) {
  if (messenger == null) {
    // Neither throw nor swallow: a wiring mistake (bad context, or a cold-start
    // deep link firing before the app has built) must not take a live room
    // down, but a toast vanishing without trace is how it survives to
    // production. The dropped copy rides along so the log says what the user
    // should have seen.
    reportNonFatal(
      StateError('No ScaffoldMessenger available — a ${kind.name} toast was dropped'),
      StackTrace.current,
      during: 'showing the toast "$message"',
    );
    return;
  }
  // Quiet on purpose, unlike the null case above: an unmounted messenger is a
  // teardown race, not a mistake, and logging those is the noise that stops
  // people reading logs at all.
  if (!messenger.mounted) return;

  final width = MediaQuery.sizeOf(messenger.context).width;
  final side = math.max(16.0, (width - 520) / 2);

  final (Color background, Color border, Color accent, IconData icon) = switch (kind) {
    PTSnackKind.success => (
      const Color(0xF20F1B14),
      PTColors.online.withValues(alpha: 0.35),
      PTColors.online,
      Symbols.check_circle_rounded,
    ),
    PTSnackKind.error => (
      const Color(0xF2241315),
      PTColors.dangerBorder.withValues(alpha: 0.35),
      PTColors.danger,
      Symbols.error_rounded,
    ),
    PTSnackKind.info => (
      const Color(0xF216112B),
      PTColors.white(0.16),
      PTColors.textAccent,
      Symbols.info_rounded,
    ),
  };

  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        // The container below *is* the toast; the SnackBar is only a host.
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: .floating,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.fromLTRB(side, 0, side, 16 + bottomInset),
        dismissDirection: .horizontal,
        duration: Duration(seconds: kind == .error ? 5 : 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            spacing: 13,
            children: [
              // Shell-then-contents, as in the glass dialogs: the surface rides
              // the platform's slide, the mark settles in a beat later.
              PTEntrance(
                offset: 0,
                scaleFrom: 0.6,
                duration: PTMotion.state,
                child: Icon(icon, size: 20, fill: 1, color: accent),
              ),
              Expanded(
                child: Text(message, style: PTText.body.copyWith(fontSize: 14, height: 1.35)),
              ),
            ],
          ),
        ),
      ),
    );
}

/// Tinted glass banner (T-5 warning / reconnecting / file mismatch).
class PTBanner extends StatefulWidget {
  const PTBanner({
    super.key,
    required this.kind,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onDismiss,
    this.autoDismissAfter,
    this.spinIcon = false,
    this.pulseOnArrival = false,
    this.showActivity = false,
  });

  final PTBannerKind kind;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onDismiss;

  /// Calls [onDismiss] after this long, showing a determinate ring on the
  /// close button so the countdown is visible rather than a surprise.
  /// Ignored without an [onDismiss].
  final Duration? autoDismissAfter;

  /// Rotates the glyph continuously — the universal "working on it" cue, which
  /// is what stops the reconnecting banner reading as stuck.
  final bool spinIcon;

  /// One attention pulse on mount, for banners that must not be missed.
  final bool pulseOnArrival;

  final bool showActivity;

  @override
  State<PTBanner> createState() => _PTBannerState();
}

class _PTBannerState extends State<PTBanner> with TickerProviderStateMixin {
  AnimationController? _countdown;
  AnimationController? _spin;
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    if (widget.spinIcon) {
      _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
        ..repeat();
    }
    if (widget.pulseOnArrival) {
      _pulse = AnimationController(vsync: this, duration: PTMotion.state);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pulse != null && _pulse!.isDismissed && !reducedMotion(context)) {
      _pulse!.forward();
    }
  }

  @override
  void didUpdateWidget(PTBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoDismissAfter != oldWidget.autoDismissAfter) {
      _countdown?.dispose();
      _countdown = null;
      _startCountdown();
    }
  }

  void _startCountdown() {
    final duration = widget.autoDismissAfter;
    if (duration == null || widget.onDismiss == null) return;
    _countdown = AnimationController(vsync: this, duration: duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDismiss!.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _countdown?.dispose();
    _spin?.dispose();
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final icon = widget.icon;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final trailing = widget.trailing;
    final onDismiss = widget.onDismiss;
    final (Color bg, Color border, Color iconColor) = switch (kind) {
      PTBannerKind.warning => (
        const Color(0xBF2A200E),
        PTColors.warningBorder.withValues(alpha: 0.35),
        PTColors.warning,
      ),
      PTBannerKind.info => (const Color(0xBF141022), PTColors.white(0.14), PTColors.textAccent),
      PTBannerKind.error => (
        const Color(0xB82A1414),
        PTColors.dangerBorder.withValues(alpha: 0.35),
        PTColors.danger,
      ),
    };

    final spin = _spin;
    Widget glyph = Icon(icon, size: 22, fill: 1, color: iconColor);
    if (spin != null) glyph = RotationTransition(turns: spin, child: glyph);

    Widget banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 40,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        spacing: 14,
        children: [
          glyph,
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(title, style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600)),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: PTText.body.copyWith(fontSize: 12.5, color: PTColors.white(0.6)),
                  ),
              ],
            ),
          ),
          if (widget.showActivity) const TypingDots(size: 5),
          if (trailing != null) trailing,
          if (onDismiss != null) _dismissButton(onDismiss, iconColor),
        ],
      ),
    );

    final pulse = _pulse;
    if (pulse != null) {
      banner = ScaleTransition(
        scale: TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.02), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.02, end: 1.0), weight: 1),
        ]).animate(CurvedAnimation(parent: pulse, curve: PTMotion.emphasized)),
        child: banner,
      );
    }
    return banner;
  }

  Widget _dismissButton(VoidCallback onDismiss, Color accent) {
    final countdown = _countdown;
    final close = Icon(Icons.close_rounded, size: 18, color: PTColors.white(0.45));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onDismiss,
        child: countdown == null
            ? close
            : SizedBox.square(
                dimension: 28,
                child: Stack(
                  alignment: .center,
                  children: [
                    // Drains clockwise, so "how much time is left" is readable
                    // at a glance without reading anything.
                    AnimatedBuilder(
                      animation: countdown,
                      builder: (context, _) => CircularProgressIndicator(
                        value: 1 - countdown.value,
                        strokeWidth: 2,
                        backgroundColor: PTColors.white(0.12),
                        valueColor: AlwaysStoppedAnimation(accent.withValues(alpha: 0.75)),
                      ),
                    ),
                    close,
                  ],
                ),
              ),
      ),
    );
  }
}
