import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand tokens sampled from the app icon (assets/icon/renard.jpeg) — a
/// warm orange fox on a soft white background, thick black linework.
class AppColors {
  AppColors._();

  static const orange = Color(0xFFFC842D);
  static const orangeDark = Color(0xFFE06B1A);
  static const ink = Color(0xFF1C1B17);
  static const cream = Color(0xFFFFF8F0);
  static const surface = Color(0xFFFFFFFF);
  static const blush = Color(0xFFF59182);

  /// Categorical chart palette (pie/line series identity), validated with
  /// the dataviz skill's checker for the adjacent-pairs standard — lightness
  /// band, chroma floor, CVD separation (ΔE 22+) and normal-vision
  /// separation all pass. Contrast-vs-surface is a WARN, mitigated by
  /// always pairing colors with a direct text label (never color alone) —
  /// see the pie chart legend in home_screen.dart.
  static const chartPalette = <Color>[
    orange, // brand orange (fox fur)
    Color(0xFFA8432B), // terracotta / rust
    Color(0xFFD9A441), // amber / gold
    Color(0xFF8A4224), // deep mahogany
    Color(0xFFE0806F), // dusty coral (fox blush)
  ];

  /// Picks readable ink or white text for a label sitting on [background]
  /// (e.g. a chart slice) — the chart palette mixes light and dark warm
  /// tones, so no single label color works across all of them.
  static Color labelColorOn(Color background) {
    return background.computeLuminance() > 0.22 ? ink : Colors.white;
  }
}

/// Groovy, soft, generous: big rounded shapes, warm shadows, a rounded
/// friendly display font, and a black-on-orange duotone for primary
/// actions (white-on-orange fails contrast — see theme notes below).
ThemeData buildAppTheme() {
  final textTheme = GoogleFonts.fredokaTextTheme().apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  const radius = 24.0;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.orange,
    brightness: Brightness.light,
    primary: AppColors.orange,
    onPrimary: AppColors.ink,
    secondary: AppColors.ink,
    onSecondary: Colors.white,
    tertiary: AppColors.blush,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.cream,
    textTheme: textTheme,
    fontFamily: GoogleFonts.fredoka().fontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.fredoka(
        color: AppColors.ink,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 3,
      shadowColor: AppColors.orange.withValues(alpha: 0.28),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: AppColors.ink,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        textStyle: GoogleFonts.fredoka(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.ink, width: 2),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.fredoka(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.orangeDark,
        textStyle: GoogleFonts.fredoka(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cream,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.orange, width: 2),
      ),
      labelStyle: GoogleFonts.fredoka(color: AppColors.ink.withValues(alpha: 0.7)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.orange : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? AppColors.orange.withValues(alpha: 0.4) : null,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.orange,
      thumbColor: AppColors.orange,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      titleTextStyle: GoogleFonts.fredoka(
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cream,
      labelStyle: GoogleFonts.fredoka(color: AppColors.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide.none,
    ),
    dividerTheme: DividerThemeData(color: AppColors.ink.withValues(alpha: 0.1)),
  );
}
