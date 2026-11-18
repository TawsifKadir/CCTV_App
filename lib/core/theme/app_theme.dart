import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Builds the light (reference) and dark themes.
class AppTheme {
  AppTheme._();

  /// Bundled font family (assets/fonts), so text renders identically
  /// offline and nothing is downloaded at runtime.
  static const fontFamily = 'Inter';

  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static TextTheme _textTheme(AppPalette p) {
    TextStyle heading(double size, FontWeight w, {double h = 1.25}) =>
        TextStyle(fontFamily: fontFamily, fontSize: size, fontWeight: w, height: h, color: p.text, letterSpacing: -0.2);

    TextStyle body(double size, FontWeight w, {Color? c, double h = 1.45}) =>
        TextStyle(fontFamily: fontFamily, fontSize: size, fontWeight: w, height: h, color: c ?? p.text);

    return TextTheme(
      displayLarge: heading(44, FontWeight.w600, h: 1.1),
      displayMedium: heading(36, FontWeight.w600, h: 1.1),
      displaySmall: heading(30, FontWeight.w600),
      headlineLarge: heading(28, FontWeight.w600),
      headlineMedium: heading(24, FontWeight.w600),
      headlineSmall: heading(20, FontWeight.w600),
      titleLarge: heading(18, FontWeight.w600),
      titleMedium: heading(16, FontWeight.w600),
      titleSmall: heading(14, FontWeight.w600),
      bodyLarge: body(16, FontWeight.w400),
      bodyMedium: body(14, FontWeight.w400),
      bodySmall: body(12.5, FontWeight.w400, c: p.textMuted),
      labelLarge: body(15, FontWeight.w600, h: 1.2),
      labelMedium: body(13, FontWeight.w500, h: 1.2),
      labelSmall: body(11.5, FontWeight.w500, c: p.textMuted, h: 1.2),
    );
  }

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final textTheme = _textTheme(p);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: brightness == Brightness.dark ? p.accent : AppColors.primary,
      onPrimary: AppColors.white,
      secondary: AppColors.primarySoft,
      onSecondary: AppColors.white,
      error: AppColors.error,
      onError: AppColors.white,
      surface: p.card,
      onSurface: p.text,
      onSurfaceVariant: p.textMuted,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.card,
      surfaceContainer: p.card,
      surfaceContainerHigh: p.backgroundAlt,
      surfaceContainerHighest: p.backgroundAlt,
      primaryContainer: p.accentTint,
      onPrimaryContainer: brightness == Brightness.dark ? AppColors.primarySoft : AppColors.primaryDark,
      outline: p.border,
      outlineVariant: p.border,
      shadow: Colors.black,
      inverseSurface: p.nav,
      onInverseSurface: AppColors.white,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: Radii.mdAll,
      borderSide: BorderSide(color: p.border, width: 1.2),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      textTheme: textTheme,
      extensions: [p],
      // InkRipple instead of InkSparkle: the sparkle effect runs a fragment
      // shader that must be compiled on first use (a visible hitch on
      // Android) and repaints every frame while active.
      splashFactory: InkRipple.splashFactory,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        hintStyle: textTheme.bodyMedium?.copyWith(color: p.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: p.textMuted),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.error),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
        errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.error, width: 1.2)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.error, width: 1.6)),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: p.textMuted, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.white : p.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : p.backgroundAlt,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: p.backgroundAlt,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.15),
        valueIndicatorColor: p.nav,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: p.backgroundAlt,
        circularTrackColor: p.backgroundAlt,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.lgAll),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.nav,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.white),
        shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
        textStyle: textTheme.bodyMedium,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: Radii.lgAll),
        rangeSelectionBackgroundColor: AppColors.primary.withValues(alpha: 0.18),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.16),
          selectedForegroundColor: brightness == Brightness.dark ? AppColors.primarySoft : AppColors.primary,
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.card,
        selectedColor: p.nav,
        side: BorderSide(color: p.border),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.nav, borderRadius: Radii.smAll),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.white),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.3),
        selectionHandleColor: AppColors.primary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
