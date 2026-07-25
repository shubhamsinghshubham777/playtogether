import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';

/// Layout classes matching the design artboards:
/// desktop 1440×900 · portrait 390×844 · landscape 844×390.
enum PTLayout { desktop, portrait, landscape }

const kMobileBreakpoint = 'MOBILE';
const kDesktopBreakpoint = 'DESKTOP';

PTLayout layoutOf(BuildContext context) {
  if (ResponsiveBreakpoints.of(context).largerOrEqualTo(kDesktopBreakpoint)) {
    return .desktop;
  }
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height ? .landscape : .portrait;
}

/// Wraps the router child; installs the breakpoints used by [layoutOf].
Widget buildResponsiveWrapper(BuildContext context, Widget? child) {
  return ResponsiveBreakpoints.builder(
    child: child ?? const SizedBox.shrink(),
    breakpoints: const [
      Breakpoint(start: 0, end: 839, name: kMobileBreakpoint),
      Breakpoint(start: 840, end: double.infinity, name: kDesktopBreakpoint),
    ],
  );
}

/// Chooses the per-layout builder; falls back desktop→landscape→portrait.
class PTResponsive extends StatelessWidget {
  const PTResponsive({super.key, required this.portrait, this.landscape, this.desktop});

  final WidgetBuilder portrait;
  final WidgetBuilder? landscape;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    return switch (layoutOf(context)) {
      .desktop => (desktop ?? landscape ?? portrait)(context),
      .landscape => (landscape ?? desktop ?? portrait)(context),
      .portrait => portrait(context),
    };
  }
}
