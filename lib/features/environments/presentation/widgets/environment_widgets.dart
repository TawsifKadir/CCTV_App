import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/environment_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../connectivity/connectivity_service.dart';
import '../../../connectivity/connectivity_widgets.dart';
import '../providers/environment_providers.dart';

Color environmentColor(EnvironmentConfig env) {
  if (env.isProduction) return AppColors.success;
  return switch (env.environmentId) {
    'local' => AppColors.peach,
    'development' => AppColors.info,
    'qa' => AppColors.warning,
    _ => AppColors.muted,
  };
}

/// Pill showing the active environment, e.g. "LOCAL".
class EnvironmentBadge extends ConsumerWidget {
  const EnvironmentBadge({super.key, this.onDark = false, this.dense = false});

  /// Render for a dark surface (sidebar/nav).
  final bool onDark;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(activeEnvironmentProvider);
    final color = environmentColor(env);
    final t = Theme.of(context).textTheme;
    return Tooltip(
      message: '${env.environmentName} · ${env.baseUrl}',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: onDark ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_rounded, size: dense ? 11 : 13, color: onDark ? color : context.onTint(color)),
            const SizedBox(width: 5),
            Text(
              env.environmentName.toUpperCase(),
              style: t.labelSmall?.copyWith(
                color: onDark ? Colors.white : context.onTint(color),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dot + label describing the connection (device network + backend).
class ConnectionIndicator extends ConsumerWidget {
  const ConnectionIndicator({super.key, this.showLastSuccess = false, this.onDark = false});

  final bool showLastSuccess;
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    final t = Theme.of(context).textTheme;
    final (color, _) = networkStatusStyle(status.status);
    final label = status.status == NetworkStatus.online ? 'Connected' : status.status.label;
    final muted = onDark ? Colors.white60 : context.palette.textMuted;
    return Semantics(
      label: 'Backend $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: t.labelMedium?.copyWith(color: onDark ? Colors.white : null, fontWeight: FontWeight.w600),
          ),
          if (showLastSuccess && status.lastSuccessAt != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '· last OK ${Fmt.relative(status.lastSuccessAt)}',
                style: t.labelSmall?.copyWith(color: muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Thin full-width strip shown in debug-capable environments so testers
/// always know which server they are using.
class EnvironmentStrip extends ConsumerWidget {
  const EnvironmentStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(activeEnvironmentProvider);
    if (!env.allowDebugFeatures) return const SizedBox.shrink();
    final color = environmentColor(env);
    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 20,
          child: Center(
            child: Text(
              '${env.environmentName.toUpperCase()} · ${env.baseUrl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
