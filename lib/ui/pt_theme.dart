import 'package:flutter/material.dart';

/// Design tokens from the "Playtogether redesign" design system.
/// Dark mode only — glass panels rely on dark video/ambient backdrops.
abstract final class PTColors {
  // Accent — violet.
  static const textAccent = Color(0xFFC9B8FF);
  static const gradientEnd = Color(0xFFC084FC);
  static const gradientMid = Color(0xFFA855F7);
  static const primary = Color(0xFF8B5CF6);
  static const deep = Color(0xFF7C3AED);

  // Surfaces.
  static const canvas = Color(0xFF08070C);
  static const screenBg = Color(0xFF0B0A14);
  static const glassBase = Color(0xFF161226); // rgba(22,18,38,·)
  static const dialogGlassBase = Color(0xFF18132A); // rgba(24,19,42,·)
  static const avatarRing = Color(0xFF14101F);
  static const presenceRing = Color(0xFF171329);

  // Semantic.
  static const online = Color(0xFF4ADE80);
  static const away = Color(0xFF6B7280);
  static const warning = Color(0xFFFDE68A);
  static const warningBorder = Color(0xFFFACC15);
  static const danger = Color(0xFFFCA5A5);
  static const dangerBorder = Color(0xFFF87171);

  static const selectionHandle = Color(0xFF22D3EE);
  static const selectionHighlight = Color(0x7322D3EE);

  static const buttonGradient = LinearGradient(
    begin: .topLeft,
    end: .bottomRight,
    colors: [primary, gradientMid],
  );
  static const barGradient = LinearGradient(colors: [primary, gradientEnd]);
  static const brandGradient = LinearGradient(
    begin: .topLeft,
    end: .bottomRight,
    colors: [primary, gradientEnd],
  );

  static Color white(double opacity) => Colors.white.withValues(alpha: opacity);
  static Color glass(double opacity) => glassBase.withValues(alpha: opacity);
  static Color dialogGlass(double opacity) => dialogGlassBase.withValues(alpha: opacity);

  /// Per-user avatar gradients — fixed per user (hash of the user id).
  static const avatarGradients = <List<Color>>[
    [Color(0xFFA78BFA), Color(0xFF7C3AED)],
    [Color(0xFFF472B6), Color(0xFFC084FC)],
    [Color(0xFF60A5FA), Color(0xFF818CF8)],
    [Color(0xFF34D399), Color(0xFF22D3EE)],
    [Color(0xFFFBBF24), Color(0xFFF97316)],
    [Color(0xFFF87171), Color(0xFFEC4899)],
    [Color(0xFF4ADE80), Color(0xFF16A34A)],
    [Color(0xFF38BDF8), Color(0xFF6366F1)],
  ];

  static LinearGradient avatarGradientFor(String userId) {
    final colors = avatarGradients[userId.hashCode.abs() % avatarGradients.length];
    return LinearGradient(begin: .topLeft, end: .bottomRight, colors: colors);
  }
}

abstract final class PTFonts {
  static const display = 'Space Grotesk'; // display & headings
  static const body = 'Outfit'; // body & UI
  static const mono = 'JetBrains Mono'; // codes, time, meta
}

abstract final class PTText {
  static const display = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 40,
    fontWeight: .w700,
    letterSpacing: -0.8,
    color: Colors.white,
  );
  static const screenTitle = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 24,
    fontWeight: .w700,
    letterSpacing: -0.48,
    color: Colors.white,
  );
  static const cardHeading = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 19,
    fontWeight: .w600,
    color: Colors.white,
  );
  static const panelHeading = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 15,
    fontWeight: .w600,
    color: Colors.white,
  );
  static TextStyle body = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 15,
    fontWeight: .w400,
    color: PTColors.white(0.92),
  );
  static const buttonLabel = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 15,
    fontWeight: .w600,
    color: Colors.white,
  );
  static TextStyle caption = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 13,
    fontWeight: .w500,
    color: PTColors.white(0.6),
  );
  static TextStyle finePrint = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 12,
    fontWeight: .w400,
    color: PTColors.white(0.4),
  );
  static const code = TextStyle(
    fontFamily: PTFonts.mono,
    fontSize: 22,
    fontWeight: .w500,
    letterSpacing: 3.96,
    color: PTColors.textAccent,
  );
  static TextStyle mono = TextStyle(
    fontFamily: PTFonts.mono,
    fontSize: 13,
    fontWeight: .w400,
    color: PTColors.white(0.75),
  );
}

ThemeData buildPTTheme() {
  const scheme = ColorScheme.dark(
    primary: PTColors.primary,
    secondary: PTColors.gradientMid,
    surface: PTColors.screenBg,
    error: PTColors.danger,
    onPrimary: Colors.white,
    onSurface: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: .dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: PTColors.screenBg,
    fontFamily: PTFonts.body,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: PTColors.white(0.92), displayColor: Colors.white),
    sliderTheme: SliderThemeData(
      trackHeight: 5,
      activeTrackColor: PTColors.primary,
      inactiveTrackColor: PTColors.white(0.12),
      thumbColor: const Color(0xFFE9DCFF),
      overlayColor: PTColors.primary.withValues(alpha: 0.15),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    dividerTheme: DividerThemeData(color: PTColors.white(0.09), thickness: 1, space: 1),
    // Fallback only — every toast in the app goes through `showPTSnack`, which
    // supplies its own surface (see banners.dart). This just keeps a bare
    // `showSnackBar` from any future caller looking foreign.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PTColors.dialogGlass(0.95),
      contentTextStyle: PTText.body,
      behavior: .floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: PTColors.dialogGlass(0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PTColors.white(0.14)),
      ),
      textStyle: PTText.caption.copyWith(color: PTColors.white(0.85)),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: PTColors.textAccent,
      selectionColor: PTColors.selectionHighlight,
      selectionHandleColor: PTColors.selectionHandle,
    ),
  );
}
