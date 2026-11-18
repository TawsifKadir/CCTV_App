import 'package:flutter/material.dart';

/// Raw brand colours. Widgets should normally read colours through
/// [AppPalette] (`context.palette`) so light/dark themes work, but brand
/// accents and status colours are identical in both themes.
class AppColors {
  AppColors._();

  static const ivory = Color(0xFFF4F1E9);
  static const sand = Color(0xFFEAE6DA);
  static const peach = Color(0xFFFF9966);
  static const peachSoft = Color(0xFFF8A477);
  static const peachTint = Color(0xFFFFE6D9);
  static const charcoal = Color(0xFF252525);
  static const charcoalSoft = Color(0xFF333333);
  static const ink = Color(0xFF222222);
  static const muted = Color(0xFF85837E);
  static const white = Color(0xFFFFFFFF);
  static const border = Color(0xFFEAE7DF);

  static const success = Color(0xFF6FAF88);
  static const warning = Color(0xFFE8B15B);
  static const error = Color(0xFFD96C64);
  static const info = Color(0xFF7A9CC6);
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

  static const light = AppPalette(
    background: AppColors.ivory,
    backgroundAlt: AppColors.sand,
    card: AppColors.white,
    text: AppColors.ink,
    textMuted: AppColors.muted,
    border: AppColors.border,
    nav: AppColors.charcoal,
    navText: AppColors.white,
    shadow: Color(0x14000000),
    accentTint: AppColors.peachTint,
  );

  /// Warm deep-charcoal dark theme: same identity, not an inversion.
  /// Surfaces step up in lightness for elevation; the peach accent stays.
  static const dark = AppPalette(
    background: Color(0xFF171614),
    backgroundAlt: Color(0xFF221F1C),
    card: Color(0xFF242220),
    text: Color(0xFFF2EEE6),
    textMuted: Color(0xFFA8A49B),
    border: Color(0xFF36332E),
    nav: Color(0xFF0F0E0D),
    navText: AppColors.white,
    shadow: Color(0x59000000),
    accentTint: Color(0xFF3D2A20),
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
