import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Material themed to DESIGN.md: neutral surfaces, one accent, IBM Plex
/// Sans, flat cards and modest corners.
abstract final class AppTheme {
  static const String fontFamily = 'IBMPlexSans';

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static TextTheme _text(AppColors c) {
    TextStyle style(double size, FontWeight weight, double height, [Color? color]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height / size,
          color: color ?? c.text,
          letterSpacing: 0,
        );
    return TextTheme(
      displaySmall: style(32, FontWeight.w600, 38),
      headlineMedium: style(28, FontWeight.w600, 34),
      headlineSmall: style(24, FontWeight.w600, 30),
      titleLarge: style(18, FontWeight.w600, 24),
      titleMedium: style(17, FontWeight.w600, 24),
      titleSmall: style(15, FontWeight.w500, 20),
      bodyLarge: style(15, FontWeight.w400, 22),
      bodyMedium: style(14, FontWeight.w400, 20, c.text2),
      bodySmall: style(13, FontWeight.w400, 18, c.text2),
      labelLarge: style(15, FontWeight.w600, 20),
      labelMedium: style(13, FontWeight.w600, 18, c.text2),
      labelSmall: style(12, FontWeight.w500, 16, c.text2),
    );
  }

  static ThemeData _build(AppColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final text = _text(c);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: isDark ? const Color(0xFF0B1638) : Colors.white,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: isDark ? const Color(0xFFDCE4FF) : const Color(0xFF12307F),
      secondary: c.text2,
      onSecondary: c.surface,
      secondaryContainer: c.surface2,
      onSecondaryContainer: c.text,
      tertiary: c.success,
      onTertiary: Colors.white,
      error: c.danger,
      onError: isDark ? const Color(0xFF3A0B0B) : Colors.white,
      errorContainer: isDark ? const Color(0xFF3B1B1B) : const Color(0xFFFBE6E6),
      onErrorContainer: isDark ? const Color(0xFFFFD6D2) : const Color(0xFF7A1D1D),
      surface: c.bg,
      onSurface: c.text,
      onSurfaceVariant: c.text2,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface2,
      surfaceContainerHigh: c.surface2,
      surfaceContainerHighest: c.line,
      outline: c.text3,
      outlineVariant: c.line,
      inverseSurface: isDark ? const Color(0xFFECEEF2) : const Color(0xFF22252B),
      onInverseSurface: isDark ? const Color(0xFF15171B) : const Color(0xFFF1F2F4),
      inversePrimary: isDark ? const Color(0xFF1E6FE8) : const Color(0xFF3085FE),
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    final control = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.control),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      splashFactory: InkRipple.splashFactory,
      extensions: [c],
      iconTheme: IconThemeData(color: c.text2, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: Space.gutter,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: c.text),
        actionsIconTheme: IconThemeData(color: c.text2),
        systemOverlayStyle: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: c.surface,
            ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: c.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.accent : c.text2,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected) ? c.text : c.text2,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.accentSoft,
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.text2),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        minVerticalPadding: Space.m,
        horizontalTitleGap: Space.l,
        iconColor: c.text2,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface2,
        hintStyle: text.bodyLarge?.copyWith(color: c.text3),
        labelStyle: text.bodyMedium,
        floatingLabelStyle: text.bodySmall?.copyWith(color: c.accent),
        helperStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: control,
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: control,
          foregroundColor: c.text,
          side: BorderSide(color: c.line),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: control,
          foregroundColor: c.accent,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.text2),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.line,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.bg,
        selectedColor: c.accentSoft,
        side: BorderSide(color: c.line),
        labelStyle: text.bodyMedium?.copyWith(color: c.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        padding: const EdgeInsets.symmetric(horizontal: Space.s),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: c.accentSoft,
          selectedForegroundColor: c.text,
          foregroundColor: c.text2,
          side: BorderSide(color: c.line),
          shape: control,
          textStyle: text.labelMedium,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surface2,
        linearMinHeight: 4,
        circularTrackColor: c.surface2,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : c.line,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: c.text3, width: 1.5),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        textStyle: text.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(color: c.line),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.accent,
        textColor: scheme.onPrimary,
        textStyle: text.labelSmall?.copyWith(fontFeatures: tabularFigures),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
