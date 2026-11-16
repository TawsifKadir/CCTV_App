import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/motion.dart';

/// Shared hover/press scale behaviour for custom buttons.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final scale = !enabled ? 1.0 : (_down ? 0.97 : (_hover ? 1.015 : 1.0));
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: context.motion(Motion.fast),
          curve: Motion.curve,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Peach, rounded primary call-to-action with built-in loading state.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.color = AppColors.peach,
    this.foreground = AppColors.white,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final Color color;
  final Color foreground;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final radius = BorderRadius.circular(Radii.md + 2);
    final text = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: foreground);
    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: _Pressable(
        borderRadius: radius,
        onTap: disabled ? null : onPressed,
        child: AnimatedContainer(
          duration: context.motion(Motion.fast),
          height: height,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: onPressed == null ? color.withValues(alpha: 0.45) : color,
            borderRadius: radius,
            boxShadow: onPressed == null
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: AnimatedSwitcher(
                  duration: context.motion(Motion.fast),
                  child: loading
                      ? SizedBox(
                          key: const ValueKey('l'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: foreground,
                          ),
                        )
                      : Row(
                          key: const ValueKey('c'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, size: 20, color: foreground),
                              const SizedBox(width: Space.xs),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                style: text,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum AppSecondaryVariant { neutral, outline, danger, dark }

/// Secondary action: soft sand fill, outline, dark, or danger tint.
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppSecondaryVariant.neutral,
    this.expand = true,
    this.loading = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppSecondaryVariant variant;
  final bool expand;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color bg, Color fg, Color? border) = switch (variant) {
      AppSecondaryVariant.neutral => (p.backgroundAlt, p.text, null),
      AppSecondaryVariant.outline => (Colors.transparent, p.text, p.border),
      AppSecondaryVariant.danger => (
        AppColors.error.withValues(alpha: 0.12),
        AppColors.error,
        null,
      ),
      AppSecondaryVariant.dark => (p.nav, AppColors.white, null),
    };
    final radius = BorderRadius.circular(Radii.md + 2);
    final disabled = onPressed == null || loading;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: _Pressable(
          borderRadius: radius,
          onTap: disabled ? null : onPressed,
          child: Container(
            height: height,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg - 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: border == null
                  ? null
                  : Border.all(color: border, width: 1.4),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: fg,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: 19, color: fg),
                if (loading || icon != null) const SizedBox(width: Space.xs),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button used in headers and toolbars.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.background,
    this.foreground,
    this.size = 44,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? background;
  final Color? foreground;
  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: _Pressable(
          borderRadius: BorderRadius.circular(size),
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background ?? p.card,
              shape: BoxShape.circle,
              border: background == null ? Border.all(color: p.border) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: size * 0.45, color: foreground ?? p.text),
                if (badge)
                  Positioned(
                    top: size * 0.22,
                    right: size * 0.24,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.peach,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline text link in the accent colour.
class AppLinkButton extends StatelessWidget {
  const AppLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? AppColors.peach,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: Radii.smAll),
        textStyle: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
