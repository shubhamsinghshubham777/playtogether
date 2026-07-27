import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playtogether/platform.dart';
import 'package:window_manager/window_manager.dart';

/// Width to reserve at the leading edge of a desktop top bar so its content
/// clears macOS's traffic-light buttons — they float directly over the
/// Flutter view now that the native title bar is hidden (see main.dart).
double get desktopLeadingChromeInset =>
    isDesktop && defaultTargetPlatform == TargetPlatform.macOS ? 72 : 0;

/// Width to reserve at the trailing edge of a desktop top bar so its content
/// clears Windows' minimize/maximize/close buttons, which dock to the
/// window's top-right corner once the native title bar is hidden.
double get desktopTrailingChromeInset =>
    isDesktop && defaultTargetPlatform == TargetPlatform.windows ? 148 : 0;

/// Wraps a screen's top bar so the empty gaps in it (Spacers, space between
/// buttons) become a native window-drag region. With the title bar hidden
/// there is otherwise no way to reposition the window; real content in
/// [child] (buttons, pills, text) still gets its own taps — the drag layer
/// sits behind it and only catches hits nothing above claims.
class DesktopDragBar extends StatelessWidget {
  const DesktopDragBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return Stack(
      children: [
        const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
        child,
      ],
    );
  }
}
