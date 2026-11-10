import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';

/// Corner radii: cards and dialogs, then buttons and small tiles.
abstract final class GotitRadius {
  static const card = 12.0;
  static const control = 10.0;
}

/// The Slate theme for [brightness]: Material 3 on Gotit's palette, set in
/// Inter (bundled, Latin subset).
ThemeData gotitTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? GotitColors.dark
      : GotitColors.light;
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: Color.alphaBlend(c.soft, c.surface),
    onPrimaryContainer: c.accent,
    secondary: c.accent2,
    onSecondary: c.onAccent,
    tertiary: c.ok,
    onTertiary: c.onAccent,
    error: dark ? const Color(0xFFFF6B5E) : const Color(0xFFD92D20),
    onError: dark ? c.bg : const Color(0xFFFFFFFF),
    surface: c.bg,
    onSurface: c.fg,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface2,
    surfaceContainerHighest: c.surface2,
    outline: dark ? const Color(0xFF2E323D) : const Color(0xFFD3D5DC),
    outlineVariant: c.line,
    inverseSurface: c.fg,
    onInverseSurface: c.bg,
    inversePrimary: c.accent2,
  );

  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c, GotitMotion.standard],
  );
  final text = base.textTheme.apply(bodyColor: c.fg, displayColor: c.fg);
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(GotitRadius.control),
  );
  const buttonText = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 15, letterSpacing: 0),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, letterSpacing: 0),
      bodySmall: text.bodySmall?.copyWith(
        fontSize: 12.5,
        letterSpacing: 0,
        color: c.muted,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelSmall: text.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
        color: c.muted,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GotitRadius.card),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(64, 44),
        shape: controlShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.fg,
        minimumSize: const Size(64, 44),
        side: BorderSide(color: c.line),
        shape: controlShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        shape: controlShape,
        textStyle: buttonText,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.surface2,
      circularTrackColor: c.surface2,
      linearMinHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.accent : c.surface2,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0x00000000)),
    ),
    iconTheme: IconThemeData(color: c.muted, size: 20),
  );
}
