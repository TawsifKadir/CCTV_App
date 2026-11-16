import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/motion.dart';

/// Rounded white surface with soft shadow; lifts slightly on hover.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg - 4),
    this.onTap,
    this.color,
    this.radius = Radii.lg,
    this.border = false,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final bool border;
  final Gradient? gradient;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final interactive = widget.onTap != null;
    final lifted = interactive && _hover;
    final radius = BorderRadius.circular(widget.radius);
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => setState(() => _hover = true) : null,
      onExit: interactive ? (_) => setState(() => _hover = false) : null,
      child: AnimatedContainer(
        duration: context.motion(Motion.fast),
        curve: Motion.curve,
        transform: Matrix4.translationValues(0, lifted ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: widget.gradient == null ? (widget.color ?? p.card) : null,
          gradient: widget.gradient,
          borderRadius: radius,
          border: widget.border ? Border.all(color: p.border) : null,
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: lifted ? p.shadow.a * 1.8 : p.shadow.a),
              blurRadius: lifted ? 28 : 18,
              offset: Offset(0, lifted ? 12 : 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Animated integer counter (respects reduced motion).
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: context.motion(const Duration(milliseconds: 900)),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(v.round().toString(), style: style),
    );
  }
}

/// Dashboard statistic tile.
class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = AppColors.peach,
    this.caption,
    this.dark = false,
    this.onTap,
    this.loading = false,
  });

  final String label;

  /// `null` = unavailable (shown as "—", never as 0).
  final int? value;

  /// Shows a placeholder while the figure is being fetched.
  final bool loading;
  final IconData icon;
  final Color accent;
  final String? caption;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final fg = dark ? AppColors.white : p.text;
    final muted = dark ? AppColors.white.withValues(alpha: 0.65) : p.textMuted;
    return AppCard(
      onTap: onTap,
      color: dark ? p.nav : null,
      padding: const EdgeInsets.all(Space.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(icon, size: 21, color: accent),
              ),
              const Spacer(),
              if (onTap != null) Icon(Icons.arrow_outward_rounded, size: 18, color: muted),
            ],
          ),
          const SizedBox(height: Space.md),
          SizedBox(
            height: 34,
            child: Align(
              alignment: Alignment.centerLeft,
              child: loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
                    )
                  : value == null
                      ? Text('—', style: t.headlineLarge?.copyWith(color: muted, height: 1))
                      : AnimatedCount(value: value!, style: t.headlineLarge?.copyWith(color: fg, height: 1)),
            ),
          ),
          const SizedBox(height: Space.xxs),
          Text(label, style: t.labelMedium?.copyWith(color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: t.bodySmall?.copyWith(color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// Small coloured dot + label pill used for statuses and tags.
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.showDot = true,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: dense ? 12 : 14, color: context.onTint(color))
          else if (showDot)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          if (icon != null || showDot) SizedBox(width: dense ? 4 : 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (dense ? t.labelSmall : t.labelMedium)?.copyWith(
                color: context.onTint(color),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
