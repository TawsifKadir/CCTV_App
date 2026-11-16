import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_cards.dart';

/// Titled card grouping related settings.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children, this.icon});

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: Space.xs),
          child: Text(title.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) Divider(color: context.palette.border, height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Single settings row with icon, text and optional trailing control.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
    this.below,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;

  /// Extra content (e.g. a slider) under the row.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = color ?? AppColors.peach;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: Radii.smAll),
                  child: Icon(icon, size: 20, color: c),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.labelLarge?.copyWith(color: color == AppColors.error ? AppColors.error : null)),
                      if (subtitle != null) Text(subtitle!, style: t.bodySmall),
                    ],
                  ),
                ),
                ?trailing,
                if (trailing == null && onTap != null)
                  Icon(Icons.chevron_right_rounded, color: context.palette.textMuted),
              ],
            ),
            ?below,
          ],
        ),
      ),
    );
  }
}

/// Switch row.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      color: color,
      onTap: () => onChanged(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}
