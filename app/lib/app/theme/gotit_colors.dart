import 'package:flutter/material.dart';

/// Slate, Gotit's palette: dark-first and precise, with an indigo-to-violet
/// gradient for anything live. Widgets read colours from here (or from the
/// [ColorScheme] built on it), never from hard-coded values.
@immutable
class GotitColors extends ThemeExtension<GotitColors> {
  const GotitColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.fg,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accent2,
    required this.onAccent,
    required this.soft,
    required this.ok,
  });

  /// Window and screen background.
  final Color bg;

  /// Cards and lists.
  final Color surface;

  /// Raised or pressed surfaces, tracks.
  final Color surface2;

  /// Main text.
  final Color fg;

  /// Secondary text and icons.
  final Color muted;

  /// Hairlines and borders.
  final Color line;

  /// Indigo: actions, links, live things.
  final Color accent;

  /// Violet: the far end of the live gradient.
  final Color accent2;

  /// Text and icons on [accent].
  final Color onAccent;

  /// A faint accent wash behind accent icons.
  final Color soft;

  /// Connected and done.
  final Color ok;

  /// The gradient for live things: the switch, the link beam, progress.
  LinearGradient get live => LinearGradient(colors: [accent, accent2]);

  static const light = GotitColors(
    bg: Color(0xFFF7F7F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F2F5),
    fg: Color(0xFF0B0C10),
    muted: Color(0xFF5F6576),
    line: Color(0xFFE4E5EA),
    accent: Color(0xFF4F5BEF),
    accent2: Color(0xFF8B5CF6),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0x1A4F5BEF),
    ok: Color(0xFF12A150),
  );

  static const dark = GotitColors(
    bg: Color(0xFF0A0B0E),
    surface: Color(0xFF111318),
    surface2: Color(0xFF181B22),
    fg: Color(0xFFECEEF2),
    muted: Color(0xFF8A90A2),
    line: Color(0xFF22262F),
    accent: Color(0xFF7C86FF),
    accent2: Color(0xFFB18CFF),
    onAccent: Color(0xFF0A0B0E),
    soft: Color(0x247C86FF),
    ok: Color(0xFF3DD68C),
  );

  /// The palette in [context]'s theme, or the stock one for its brightness.
  static GotitColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GotitColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  GotitColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? fg,
    Color? muted,
    Color? line,
    Color? accent,
    Color? accent2,
    Color? onAccent,
    Color? soft,
    Color? ok,
  }) => GotitColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    fg: fg ?? this.fg,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2,
    onAccent: onAccent ?? this.onAccent,
    soft: soft ?? this.soft,
    ok: ok ?? this.ok,
  );

  @override
  GotitColors lerp(GotitColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return GotitColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      fg: mix(fg, other.fg),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      accent: mix(accent, other.accent),
      accent2: mix(accent2, other.accent2),
      onAccent: mix(onAccent, other.onAccent),
      soft: mix(soft, other.soft),
      ok: mix(ok, other.ok),
    );
  }
}
