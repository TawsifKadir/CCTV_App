import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../connectivity/connectivity_service.dart';
import '../../employees/data/models/employee_record.dart';
import '../../employees/data/models/local_employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../data/sync_engine.dart';
import 'sync_providers.dart';

/// "On server / Local only / Sync pending / Sync failed / Needs review".
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key, required this.record, this.dense = true});
  final EmployeeRecord record;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = record.status;
    final review = record.local?.needsReconciliation == true && s == SyncStatus.failed;
    return AppPill(
      key: Key('sync-badge-${s.code}'),
      label: record.statusLabel,
      color: review ? AppColors.warning : s.color,
      icon: review ? Icons.help_outline_rounded : s.icon,
      dense: dense,
    );
  }
}

/// Starts "Sync now" from anywhere. Never starts a doomed upload: when the
/// server can't be reached it explains that records are safe and offers
/// Retry connection / Try again / Cancel.
Future<void> runSyncNow(BuildContext context, WidgetRef ref, {SyncSelection selection = SyncSelection.manual}) async {
  final controller = ref.read(syncControllerProvider.notifier);
  final (start, _) = selection == SyncSelection.failedOnly ? await controller.retryFailed() : await controller.sync(selection: selection);
  if (!context.mounted) return;
  switch (start) {
    case SyncStart.offline:
      await showOfflineSyncDialog(context, ref, selection: selection);
    case SyncStart.nothingToSync:
      showAppSnack(context, 'Everything is up to date. No employees are waiting to synchronize.', type: SnackType.success);
    case SyncStart.alreadyRunning:
      showAppSnack(context, 'Synchronization is already in progress.');
    case SyncStart.started:
      break; // the controller reports the result
  }
}

Future<void> showOfflineSyncDialog(BuildContext context, WidgetRef ref, {SyncSelection selection = SyncSelection.manual}) async {
  final pending = ref.read(localCountsProvider).awaiting;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      return Dialog(
        key: const Key('offline-sync-dialog'),
        insetPadding: const EdgeInsets.all(Space.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.13), shape: BoxShape.circle),
                  child: const Icon(Icons.cloud_off_rounded, color: AppColors.info, size: 28),
                ),
                const SizedBox(height: Space.md),
                Text('You are currently offline', style: t.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: Space.xs),
                Text(
                  'Your records are safely stored on this device'
                  '${pending > 0 ? ' ($pending waiting)' : ''}. You can retry synchronization when the server '
                  'becomes available.',
                  style: t.bodyMedium?.copyWith(color: ctx.palette.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.lg),
                AppPrimaryButton(
                  key: const Key('offline-retry-connection'),
                  label: 'Retry connection',
                  icon: Icons.wifi_tethering_rounded,
                  height: 48,
                  onPressed: () => Navigator.pop(ctx, 'connection'),
                ),
                const SizedBox(height: Space.sm),
                Row(children: [
                  Expanded(
                    child: AppSecondaryButton(label: 'Cancel', height: 46, onPressed: () => Navigator.pop(ctx)),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: AppSecondaryButton(
                      label: 'Try again',
                      icon: Icons.sync_rounded,
                      height: 46,
                      variant: AppSecondaryVariant.outline,
                      onPressed: () => Navigator.pop(ctx, 'sync'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
    },
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'connection') {
    await ref.read(connectionStatusProvider.notifier).check();
    if (!context.mounted) return;
    final s = ref.read(connectionStatusProvider);
    showAppSnack(
      context,
      s.isOnline ? 'Connected to the server. You can synchronize now.' : 'Still unable to reach the server.',
      type: s.isOnline ? SnackType.success : SnackType.warning,
    );
  } else {
    await runSyncNow(context, ref, selection: selection);
  }
}

/// Peach "Sync now" button with live progress and pending count.
class SyncNowButton extends ConsumerWidget {
  const SyncNowButton({super.key, this.expand = false, this.height = 46, this.dark = false});
  final bool expand;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final waiting = ref.watch(syncableCountProvider);
    final p = sync.progress;
    final label = sync.running
        ? (p == null || p.total == 0 ? 'Syncing…' : 'Syncing ${p.done}/${p.total}…')
        : (waiting > 0 ? 'Sync now ($waiting)' : 'Sync now');
    return AppPrimaryButton(
      key: const Key('sync-now'),
      label: label,
      icon: Icons.sync_rounded,
      expand: expand,
      height: height,
      loading: sync.running,
      onPressed: sync.running ? null : () => runSyncNow(context, ref),
    );
  }
}

/// Small top-bar summary: pending count that opens the sync screen.
class PendingSyncChip extends ConsumerWidget {
  const PendingSyncChip({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(localCountsProvider);
    final running = ref.watch(syncControllerProvider.select((s) => s.running));
    if (counts.awaiting == 0 && !running) return const SizedBox.shrink();
    final color = counts.failed > 0 ? AppColors.error : AppColors.info;
    final t = Theme.of(context).textTheme;
    return Tooltip(
      message: 'Employees waiting to synchronize',
      child: InkWell(
        key: const Key('pending-chip'),
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: () => context.go(Routes.sync),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: onDark ? 0.24 : 0.14),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(running ? Icons.sync_rounded : Icons.cloud_upload_outlined, size: 14, color: onDark ? color : context.onTint(color)),
            const SizedBox(width: 5),
            Text(
              running ? 'Syncing' : '${counts.awaiting} pending',
              style: t.labelSmall?.copyWith(color: onDark ? Colors.white : context.onTint(color), fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      ),
    );
  }
}
