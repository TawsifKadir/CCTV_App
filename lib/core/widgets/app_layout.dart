import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/responsive.dart';

/// Section title with optional trailing action.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleLarge),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: t.bodySmall),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: AppColors.peach),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: t.labelMedium?.copyWith(color: AppColors.peach, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Large page title used at the top of top-level screens.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg - 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Space.sm)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.isMobile ? t.headlineMedium : t.headlineLarge),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle!, style: t.bodyMedium?.copyWith(color: context.palette.textMuted)),
                  ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: Space.xs), a],
        ],
      ),
    );
  }
}

/// Scrollable page body with responsive padding and max width.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.children, this.maxWidth = 1240, this.controller, this.bottomPadding});

  final List<Widget> children;
  final double maxWidth;
  final ScrollController? controller;
  final double? bottomPadding;

  @override
  Widget build(BuildContext context) {
    final pad = context.pagePadding;
    final bottomNavSpace = context.useSidebar ? Space.xl : 120.0;
    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(pad, context.isMobile ? Space.md : Space.xl, pad, bottomPadding ?? bottomNavSpace),
      child: MaxWidthBox(
        maxWidth: maxWidth,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

/// Soft decorative blobs behind content (as in the reference design).
class AppBackgroundDecor extends StatelessWidget {
  const AppBackgroundDecor({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: p.background)),
        Positioned(top: -120, right: -80, child: _blob(280, AppColors.peach.withValues(alpha: 0.10))),
        Positioned(bottom: -140, left: -100, child: _blob(320, p.backgroundAlt.withValues(alpha: 0.9))),
        Positioned.fill(child: child),
      ],
    );
  }

  Widget _blob(double size, Color color) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// Label/value pair used in detail views.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.icon});

  final String label;
  final String? value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: p.textMuted), const SizedBox(width: Space.sm)],
          Expanded(
            flex: 2,
            child: Text(label, style: t.bodyMedium?.copyWith(color: p.textMuted)),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 3,
            child: SelectableText(
              (value == null || value!.isEmpty) ? '—' : value!,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
