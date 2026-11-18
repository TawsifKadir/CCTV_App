import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import 'connectivity_service.dart';

(Color, IconData) networkStatusStyle(NetworkStatus s) => switch (s) {
  NetworkStatus.online => (AppColors.success, Icons.cloud_done_rounded),
  NetworkStatus.offline => (AppColors.error, Icons.wifi_off_rounded),
  NetworkStatus.serverUnavailable => (AppColors.warning, Icons.cloud_off_rounded),
  NetworkStatus.checking => (AppColors.muted, Icons.sync_rounded),
};

/// Compact "Online / Offline / Server unavailable / Checking" pill. Updates
/// automatically; rebuilds only when the visible status changes.
class ConnectivityPill extends ConsumerWidget {
  const ConnectivityPill({super.key, this.onDark = false, this.compact = false});

  final bool onDark;

  /// Icon-only on very narrow layouts (label kept for screen readers).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(networkStatusProvider);
    final (color, icon) = networkStatusStyle(status);
    final t = Theme.of(context).textTheme;
    final fg = onDark ? Colors.white : context.onTint(color);
    return Semantics(
      label: 'Connection: ${status.label}',
      liveRegion: true,
      child: Container(
        key: const Key('connectivity-pill'),
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: onDark ? 0.24 : 0.14),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: onDark ? color : context.onTint(color)),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(
                status.label,
                style: t.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Status line with last success, used on the sync/settings screens.
class ConnectionDetails extends ConsumerWidget {
  const ConnectionDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(connectionStatusProvider);
    final t = Theme.of(context).textTheme;
    return Wrap(
      spacing: Space.sm,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const ConnectivityPill(),
        Text('Network: ${s.device.label}', style: t.bodySmall),
        Text(
          s.lastSuccessAt == null ? 'No successful connection yet' : 'Last connected ${Fmt.relative(s.lastSuccessAt)}',
          style: t.bodySmall,
        ),
      ],
    );
  }
}
