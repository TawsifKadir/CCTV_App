import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../data/models/activity.dart';

/// Quick action tile.
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.accent = AppColors.primary,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final Color accent;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = filled ? Colors.white : context.palette.text;
    return AppCard(
      onTap: onTap,
      color: filled ? AppColors.primary : null,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: filled ? Colors.white.withValues(alpha: 0.22) : accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, color: filled ? Colors.white : accent, size: 22),
          ),
          const SizedBox(height: Space.sm),
          Text(
            label,
            style: t.titleSmall?.copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            caption,
            style: t.bodySmall?.copyWith(color: filled ? Colors.white70 : null),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Timeline row for the on-device activity feed.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.activity, this.isLast = false});

  final Activity activity;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: activity.type.color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(activity.type.icon, size: 17, color: activity.type.color),
              ),
              if (!isLast) Expanded(child: Container(width: 1.5, color: p.border)),
            ],
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.md, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(activity.title, style: t.labelLarge, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: Space.xs),
                      Text(Fmt.relative(activity.timestamp), style: t.labelSmall),
                    ],
                  ),
                  if (activity.subtitle != null)
                    Text(activity.subtitle!, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
