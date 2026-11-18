import 'package:flutter/material.dart';

/// Raw brand colours. Widgets should normally read colours through
/// [AppPalette] (`context.palette`) so light/dark themes work, but brand
/// accents and status colours are identical in both themes.
class AppColors {
  AppColors._();

  // SNOWTEX brand (primary = the logo's blue).
  static const primary = Color(0xFF205CA4);
  static const primaryDark = Color(0xFF174779);
  static const primarySoft = Color(0xFF4A82C6);
  static const primaryTint = Color(0xFFEAF2FC);

  /// Highlight on the dark-blue navigation surfaces (readable on primaryDark).
  static const navAccent = Color(0xFFA9CCF5);

  static const background = Color(0xFFF5F7FA);
  static const surfaceAlt = Color(0xFFEDF1F6);
  static const ink = Color(0xFF202938);
  static const muted = Color(0xFF64748B);
  static const white = Color(0xFFFFFFFF);
  static const border = Color(0xFFE1E6EE);

  static const success = Color(0xFF249B69);
  static const warning = Color(0xFFE5A23B);
  static const error = Color(0xFFD94B4B);
  static const info = Color(0xFF3B82C4);

  /// Brand gradient (deep → logo blue) for hero surfaces. Same palette,
  /// just given depth.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF133C69), primaryDark, primary],
    stops: [0, 0.45, 1],
  );

  /// Vertical variant for the navigation sidebar.
  static const navGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryDark, Color(0xFF123A66)],
  );

  /// Primary call-to-action gradient (subtle, left → right).
  static const actionGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primary, Color(0xFF2C6DBB)],
  );
}

/// Theme-dependent surface/text colours exposed as a [ThemeExtension].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.backgroundAlt,
    required this.card,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.nav,
    required this.navText,
    required this.shadow,
    required this.accentTint,
    required this.accent,
  });

  final Color background;
  final Color backgroundAlt;
  final Color card;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color nav;
  final Color navText;
  final Color shadow;
  final Color accentTint;

  /// Brand blue for icons, links and highlights on this theme's surfaces
  /// (lighter in dark mode for contrast).
  final Color accent;

  static const light = AppPalette(
    background: AppColors.background,
    backgroundAlt: AppColors.surfaceAlt,
    card: AppColors.white,
    text: AppColors.ink,
    textMuted: AppColors.muted,
    border: AppColors.border,
    nav: AppColors.primaryDark,
    navText: AppColors.white,
    shadow: Color(0x12172B4D),
    accentTint: AppColors.primaryTint,
    accent: AppColors.primary,
  );

  /// Dark navy theme: same SNOWTEX identity, readable contrast.
  static const dark = AppPalette(
    background: Color(0xFF0E1726),
    backgroundAlt: Color(0xFF16233A),
    card: Color(0xFF152238),
    text: Color(0xFFEAF0F8),
    textMuted: Color(0xFF9FB0C8),
    border: Color(0xFF2A3B56),
    nav: Color(0xFF0A1220),
    navText: AppColors.white,
    shadow: Color(0x55000000),
    accentTint: Color(0xFF1C3558),
    accent: Color(0xFF7DB3F0),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? backgroundAlt,
    Color? card,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? nav,
    Color? navText,
    Color? shadow,
    Color? accentTint,
    Color? accent,
  }) {
    return AppPalette(
      background: background ?? this.background,
      backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      card: card ?? this.card,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      nav: nav ?? this.nav,
      navText: navText ?? this.navText,
      shadow: shadow ?? this.shadow,
      accentTint: accentTint ?? this.accentTint,
      accent: accent ?? this.accent,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      backgroundAlt: Color.lerp(backgroundAlt, other.backgroundAlt, t)!,
      card: Color.lerp(card, other.card, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      nav: Color.lerp(nav, other.nav, t)!,
      navText: Color.lerp(navText, other.navText, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Readable text colour for a status colour shown on its own tint
  /// (darker in light mode, lighter in dark mode).
  Color onTint(Color status) => Color.lerp(status, isDark ? Colors.white : Colors.black, isDark ? 0.3 : 0.28)!;
}
