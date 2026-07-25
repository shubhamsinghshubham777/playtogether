import 'package:flutter/material.dart';

import 'identity.dart';
import 'pt_theme.dart';

enum PTBannerKind { warning, info, error }

/// Tinted glass banner (T-5 warning / reconnecting / file mismatch).
class PTBanner extends StatelessWidget {
  const PTBanner({
    super.key,
    required this.kind,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onDismiss,
  });

  final PTBannerKind kind;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
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
                    subtitle!,
                    style: PTText.body.copyWith(fontSize: 12.5, color: PTColors.white(0.6)),
                  ),
              ],
            ),
          ),
          if (kind == .info) const TypingDots(size: 5),
          if (trailing != null) trailing!,
          if (onDismiss != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onDismiss,
                child: Icon(Icons.close_rounded, size: 18, color: PTColors.white(0.45)),
              ),
            ),
        ],
      ),
    );
  }
}
