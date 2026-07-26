import 'package:flutter/material.dart';

import 'identity.dart';
import 'pt_theme.dart';

enum PTBannerKind { warning, info, error }

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

  @override
  State<PTBanner> createState() => _PTBannerState();
}

class _PTBannerState extends State<PTBanner> with SingleTickerProviderStateMixin {
  AnimationController? _countdown;

  @override
  void initState() {
    super.initState();
    _startCountdown();
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
      PTBannerKind.info => (
        const Color(0xBF141022),
        PTColors.white(0.14),
        PTColors.textAccent,
      ),
      PTBannerKind.error => (
        const Color(0xB82A1414),
        PTColors.dangerBorder.withValues(alpha: 0.35),
        PTColors.danger,
      ),
    };

    return Container(
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
          Icon(icon, size: 22, fill: 1, color: iconColor),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: PTText.body.copyWith(fontSize: 12.5, color: PTColors.white(0.6)),
                  ),
              ],
            ),
          ),
          if (kind == .info) const TypingDots(size: 5),
          if (trailing != null) trailing,
          if (onDismiss != null) _dismissButton(onDismiss, iconColor),
        ],
      ),
    );
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
