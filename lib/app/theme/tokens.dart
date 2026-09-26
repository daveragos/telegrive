import 'package:flutter/material.dart';

/// The design tokens from DESIGN.md. Screens reach for these rather than
/// inventing their own numbers, so spacing, shape and colour stay one system.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 40;

  /// Left and right margin of every screen.
  static const double gutter = 20;
}

abstract final class Radii {
  static const double thumb = 6;
  static const double control = 10;
  static const double card = 14;
  static const double sheet = 16;
}

/// Numbers that must line up in columns: sizes, counts, progress.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// The palette as named roles. Material's ColorScheme covers most of them;
/// this carries the ones it has no slot for, and gives every role the name
/// DESIGN.md uses.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.danger,
  });

  static const light = AppColors(
    bg: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEF0F3),
    line: Color(0xFFE1E4E9),
    text: Color(0xFF15171B),
    text2: Color(0xFF5A6170),
    text3: Color(0xFF868D9A),
    accent: Color(0xFF2356E0),
    accentSoft: Color(0xFFE4EAFB),
    success: Color(0xFF1D8551),
    danger: Color(0xFFC23636),
  );

  static const dark = AppColors(
    bg: Color(0xFF111317),
    surface: Color(0xFF181B20),
    surface2: Color(0xFF20242A),
    line: Color(0xFF2B3038),
    text: Color(0xFFECEEF2),
    text2: Color(0xFFA3AAB6),
    text3: Color(0xFF737B88),
    accent: Color(0xFF8FA9FF),
    accentSoft: Color(0xFF1F2A47),
    success: Color(0xFF5CC48E),
    danger: Color(0xFFFF8A80),
  );

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;

  /// Selected rows and the active nav item: the accent, barely.
  final Color accentSoft;
  final Color success;
  final Color danger;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? danger,
  }) => AppColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    line: line ?? this.line,
    text: text ?? this.text,
    text2: text2 ?? this.text2,
    text3: text3 ?? this.text3,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    success: success ?? this.success,
    danger: danger ?? this.danger,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      line: mix(line, other.line),
      text: mix(text, other.text),
      text2: mix(text2, other.text2),
      text3: mix(text3, other.text3),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
