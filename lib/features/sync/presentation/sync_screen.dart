import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_layout.dart';
import '../../connectivity/app_features_provider.dart';
import '../../connectivity/connectivity_service.dart';
import '../../connectivity/connectivity_widgets.dart';
import '../../employees/data/models/employee_record.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../employees/presentation/widgets/employee_list_widgets.dart';
import '../../environments/presentation/providers/environment_providers.dart';
import '../data/sync_engine.dart';
import '../data/sync_history.dart';
import 'sync_providers.dart';
import 'sync_widgets.dart';

/// Connection status, sync statistics, pending records, actions and
/// history. Offline is presented as a safe state, not an error.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(appFeaturesProvider);
    final counts = ref.watch(localCountsProvider);
    final status = ref.watch(connectionStatusProvider);
    final sync = ref.watch(syncControllerProvider);
    final history = ref.watch(syncHistoryProvider);
    final pending = [
      for (final e in ref.watch(localEmployeesProvider))
        if (e.isUnsynced) EmployeeRecord(local: e),
    ];
    final wide = context.screenWidth >= 1000;

    final connection = _ConnectionCard(status: status, showEnvironment: features.environmentIndicator);
    final offline = !status.isOnline && counts.awaiting > 0 ? _OfflineCard(pending: counts.awaiting) : null;

    final stats = LayoutBuilder(
      builder: (context, c) {
        // Phones: the three figures that matter, one compact row.
        final compact = c.maxWidth < 720;
        if (compact) {
          Widget tile(String label, int v, Color accent) => Expanded(
            child: AppCard(
              border: true,
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('$v', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: accent)),
                ],
              ),
            ),
          );
          return Row(
            children: [
              tile('Pending', counts.pending + counts.localOnly + counts.syncing, AppColors.info),
              const SizedBox(width: Space.xs),
              tile('Failed', counts.failed, AppColors.error),
              const SizedBox(width: Space.xs),
              tile('Synced', counts.synced, AppColors.success),
            ],
          );
        }
        const cols = 5;
        final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
        final items = [
          AppStatCard(
            label: 'On this device',
            value: counts.total,
            icon: Icons.smartphone_rounded,
            caption: 'Registered here',
          ),
          AppStatCard(
            label: 'On server',
            value: counts.synced,
            icon: Icons.cloud_done_outlined,
            accent: AppColors.success,
            caption: 'Synchronized',
          ),
          AppStatCard(
            label: 'Pending',
            value: counts.pending + counts.localOnly,
            icon: Icons.cloud_upload_outlined,
            accent: AppColors.info,
            caption: 'Waiting to upload',
          ),
          AppStatCard(
            label: 'Failed',
            value: counts.failed,
            icon: Icons.error_outline_rounded,
            accent: AppColors.error,
            caption: counts.needsReview > 0 ? '${counts.needsReview} need review' : 'Safe on device',
          ),
          AppStatCard(
            label: 'Syncing',
            value: counts.syncing,
            icon: Icons.sync_rounded,
            accent: AppColors.primarySoft,
            caption: 'In progress',
          ),
        ];
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [for (final i in items) SizedBox(width: w, child: i)],
        );
      },
    );

    final p = sync.progress;
    final actions = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Actions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.md),
          const SyncNowButton(expand: true),
          if (sync.running && p != null && p.total > 0) ...[
            const SizedBox(height: Space.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(value: p.done / p.total, minHeight: 4),
            ),
            const SizedBox(height: 4),
            Text(
              p.current == null ? 'Finishing…' : 'Uploading ${p.current}…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: Space.sm),
          LayoutBuilder(
            builder: (context, c) {
              final retry = AppSecondaryButton(
                key: const Key('retry-failed'),
                label: 'Retry failed',
                icon: Icons.replay_rounded,
                height: 46,
                onPressed: counts.failed == 0 || sync.running
                    ? null
                    : () => runSyncNow(context, ref, selection: SyncSelection.failedOnly),
              );
              final check = AppSecondaryButton(
                key: const Key('refresh-connection'),
                label: 'Check connection',
                icon: Icons.wifi_tethering_rounded,
                height: 46,
                variant: AppSecondaryVariant.outline,
                loading: status.checking,
                onPressed: () => ref.read(connectionStatusProvider.notifier).check(),
              );
              // Side by side only when both labels fit without truncation.
              if (c.maxWidth < 400) {
                return Column(
                  children: [
                    retry,
                    const SizedBox(height: Space.sm),
                    check,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: retry),
                  const SizedBox(width: Space.sm),
                  Expanded(child: check),
                ],
              );
            },
          ),
          if (!ref.watch(settingsProvider).autoSync) ...[
            const SizedBox(height: Space.sm),
            Text(
              'Automatic synchronization is off. Use Sync now to upload.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );

    final pendingList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Waiting to synchronize',
          subtitle: pending.isEmpty ? null : '${pending.length} on this device',
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: pending.isEmpty
              ? const AppEmptyState(
                  compact: true,
                  icon: Icons.cloud_done_outlined,
                  title: 'All caught up',
                  message: 'Every employee registered on this device is on the server.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < pending.length; i++) ...[
                      EmployeeListTile(record: pending[i]),
                      if (features.syncDiagnostics && pending[i].local!.syncError != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 60, bottom: 6),
                          child: Text(
                            pending[i].local!.syncError!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
                          ),
                        ),
                      if (i < pending.length - 1) Divider(color: context.palette.border, height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );

    final historyCard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: 'Synchronization history'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: history.isEmpty
              ? const AppEmptyState(
                  compact: true,
                  icon: Icons.history_rounded,
                  title: 'No synchronizations yet',
                  message: 'Runs will be listed here.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < history.length && i < 20; i++) ...[
                      _HistoryTile(run: history[i], detailed: features.syncDiagnostics),
                      if (i < history.length - 1 && i < 19) Divider(color: context.palette.border, height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );

    const gap = SizedBox(height: Space.lg);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AppPage(
          maxWidth: 1180,
          children: [
            const AppPageHeader(
              title: 'Synchronization',
              subtitle: 'Upload employees saved on this device to the server.',
            ),
            if (offline != null) ...[offline, gap],
            if (!wide) ...[actions, gap],
            stats,
            gap,
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: Column(children: [pendingList, gap, historyCard])),
                  const SizedBox(width: Space.lg),
                  Expanded(flex: 2, child: Column(children: [connection, gap, actions])),
                ],
              )
            else ...[
              pendingList,
              gap,
              connection,
              gap,
              historyCard,
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({required this.status, required this.showEnvironment});
  final ConnectionStatus status;
  final bool showEnvironment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final env = ref.watch(activeEnvironmentProvider);
    final (color, icon) = networkStatusStyle(status.status);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: t.bodySmall?.copyWith(color: Colors.white60)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: t.labelMedium?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return AppCard(
      color: context.palette.nav,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text('Connection', style: t.titleMedium?.copyWith(color: Colors.white)),
              ),
              const ConnectivityPill(onDark: true),
            ],
          ),
          const SizedBox(height: Space.md),
          row('Device network', status.device.label),
          row('Server', switch (status.backendReachable) {
            true => 'Reachable',
            false => 'Not reachable',
            null => 'Not checked yet',
          }),
          if (showEnvironment) row('Environment', env.environmentName),
          row(
            'Last successful connection',
            status.lastSuccessAt == null ? 'Never' : Fmt.dateTime(status.lastSuccessAt),
          ),
          row('Last successful sync', _fmt(ref.watch(lastSuccessfulSyncProvider))),
        ],
      ),
    );
  }

  String _fmt(DateTime? d) => d == null ? 'Never' : Fmt.relative(d);
}

/// Reassuring offline state (not an error page).
class _OfflineCard extends ConsumerWidget {
  const _OfflineCard({required this.pending});
  final int pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      key: const Key('offline-card'),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.shield_outlined, color: AppColors.info, size: 30),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("You're working offline.", style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Your registrations are safely stored on this device ($pending waiting). Once the server becomes '
                  'available, you can synchronize them.',
                  style: t.bodyMedium?.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: Space.sm),
                AppPrimaryButton(
                  key: const Key('retry-sync'),
                  label: 'Retry synchronization',
                  icon: Icons.sync_rounded,
                  expand: false,
                  height: 44,
                  onPressed: () => runSyncNow(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.run, required this.detailed});
  final SyncRun run;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = run.success
        ? AppColors.success
        : (run.uploaded + run.alreadySynced > 0 ? AppColors.warning : AppColors.error);
    final summary = [
      '${run.attempted} attempted',
      '${run.uploaded} uploaded',
      if (run.alreadySynced > 0) '${run.alreadySynced} already on server',
      if (run.failed + run.uncertain > 0) '${run.failed + run.uncertain} failed',
      '${(run.duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
    ].join(' · ');
    final head = Row(
      children: [
        Icon(run.success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, color: color, size: 20),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${run.resultLabel} · ${run.trigger.label}', style: t.labelLarge),
              Text(summary, style: t.bodySmall),
            ],
          ),
        ),
        Text(Fmt.dateTime(run.startedAt), style: t.labelSmall),
      ],
    );
    if (!detailed || run.records.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: head);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: head,
        children: [
          for (final r in run.records)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text('${r.name}: ${r.outcome}${r.detail == null ? '' : ' — ${r.detail}'}', style: t.bodySmall),
              ),
            ),
          if (run.message != null) Text(run.message!, style: t.bodySmall),
        ],
      ),
    );
  }
}

/// Shortcut used by the dashboard and settings.
void openSyncScreen(BuildContext context) => context.go(Routes.sync);
