import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/motion.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_layout.dart';
import '../../authentication/providers/auth_controller.dart';
import '../../connectivity/app_features_provider.dart';
import '../../connectivity/connectivity_service.dart';
import '../../connectivity/connectivity_widgets.dart';
import '../../employees/data/models/employee.dart';
import '../../employees/data/models/employee_record.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../employees/presentation/widgets/employee_list_widgets.dart';
import '../../environments/presentation/widgets/environment_widgets.dart';
import '../../sync/presentation/sync_providers.dart';
import '../../sync/presentation/sync_widgets.dart';
import '../widgets/dashboard_widgets.dart';

/// Overview that stays useful online and offline.
///
/// Server figures are live when the server is reachable. Otherwise the last
/// known values are shown with "Last updated …" — never as current — and
/// unknown values as "—", never 0. Device figures (saved locally, awaiting
/// sync) are always live.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(appFeaturesProvider);
    final operator = ref.watch(authControllerProvider);
    final wide = context.screenWidth >= 1100;
    final name = Fmt.firstName(operator?.fullName ?? 'there');

    final header = _Header(name: name, showEnvironment: features.environmentIndicator);
    const hero = _OverviewHero();
    final stats = _StatGrid(admin: features.adminMode);
    const syncCard = _SyncStatusCard();
    final quick = _QuickActions(admin: features.adminMode);
    const recent = _RecentRegistrations();
    final serverList = features.adminMode ? const _LatestOnServer() : null;
    final activity = features.activityLog ? const _ActivityFeed() : null;
    const gap = SizedBox(height: Space.lg);

    final List<Widget> body = wide
        ? [
            header.entrance(context),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: Column(children: [
                  hero.entrance(context, index: 1),
                  gap,
                  stats,
                  gap,
                  recent.entrance(context, index: 5),
                  if (serverList != null) ...[gap, serverList],
                ]),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                flex: 2,
                child: Column(children: [
                  syncCard.entrance(context, index: 2),
                  gap,
                  quick.entrance(context, index: 3),
                  if (activity != null) ...[gap, activity],
                ]),
              ),
            ]),
          ]
        : [
            header.entrance(context),
            hero.entrance(context, index: 1),
            gap,
            stats,
            gap,
            syncCard,
            gap,
            quick,
            gap,
            recent,
            if (serverList != null) ...[gap, serverList],
            if (activity != null) ...[gap, activity],
          ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.peach,
          onRefresh: () async {
            await ref.read(connectionStatusProvider.notifier).check();
            ref.read(employeeRefresherProvider)();
          },
          child: AppPage(children: body),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.showEnvironment});
  final String name;
  final bool showEnvironment;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${Fmt.greeting()},', style: t.bodyLarge?.copyWith(color: p.textMuted)),
                Text(name, style: context.isMobile ? t.headlineMedium : t.headlineLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(Fmt.date(DateTime.now()), style: t.bodySmall),
                    const ConnectivityPill(),
                    if (showEnvironment) const EnvironmentBadge(dense: true),
                  ],
                ),
              ],
            ),
          ),
          if (context.isMobile)
            AppIconButton(
              icon: Icons.person_outline_rounded,
              tooltip: 'Profile & settings',
              onPressed: () => context.go(Routes.settings),
            ),
        ],
      ),
    );
  }
}

class _OverviewHero extends ConsumerWidget {
  const _OverviewHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final overview = ref.watch(serverOverviewProvider);
    final o = overview.valueOrNull;
    final counts = ref.watch(localCountsProvider);
    final online = ref.watch(networkStatusProvider) == NetworkStatus.online;

    final figure = overview.isLoading && o == null
        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
        : Text(
            o?.total == null ? '—' : Fmt.number(o!.total!),
            key: const Key('hero-total'),
            style: t.displayMedium?.copyWith(color: Colors.white, height: 1),
          );

    final String message;
    if (o == null) {
      message = 'Loading employee records…';
    } else if (o.fromCache) {
      message = o.total == null
          ? 'The server can\'t be reached right now. You can keep registering employees on this device.'
          : 'Employees on the server · Last updated ${Fmt.relative(o.lastRefresh)}';
    } else {
      message = o.total == 0 ? 'No employees are registered on the server yet.' : 'Employees registered on the server.';
    }

    return AppCard(
      color: p.nav,
      padding: EdgeInsets.all(context.isMobile ? Space.lg - 4 : Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Employee directory', style: t.titleMedium?.copyWith(color: Colors.white70), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: Space.xs),
            const ConnectivityPill(onDark: true),
          ]),
          const SizedBox(height: Space.md),
          figure,
          const SizedBox(height: Space.xs),
          Text(message, key: const Key('hero-message'), style: t.bodyMedium?.copyWith(color: Colors.white70)),
          if (counts.awaiting > 0) ...[
            const SizedBox(height: 4),
            Text(
              '+ ${counts.awaiting} saved on this device, waiting to synchronize',
              style: t.bodySmall?.copyWith(color: AppColors.peachSoft),
            ),
          ],
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              AppPrimaryButton(
                label: 'Register employee',
                icon: Icons.person_add_alt_1_rounded,
                expand: false,
                height: 46,
                onPressed: () => context.go(Routes.enroll),
              ),
              if (counts.awaiting > 0)
                AppSecondaryButton(
                  label: online ? 'Sync now' : 'Retry sync',
                  icon: Icons.sync_rounded,
                  variant: AppSecondaryVariant.dark,
                  expand: false,
                  height: 46,
                  onPressed: () => runSyncNow(context, ref),
                )
              else
                AppSecondaryButton(
                  label: 'View all',
                  icon: Icons.people_alt_outlined,
                  variant: AppSecondaryVariant.dark,
                  expand: false,
                  height: 46,
                  onPressed: () => context.go(Routes.employees),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends ConsumerWidget {
  const _StatGrid({required this.admin});
  final bool admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(serverOverviewProvider);
    final o = overview.valueOrNull;
    final counts = ref.watch(localCountsProvider);

    final cards = <Widget>[
      AppStatCard(
        key: const Key('stat-server'),
        label: 'On the server',
        value: o?.total,
        loading: overview.isLoading && o == null,
        icon: Icons.cloud_done_outlined,
        accent: AppColors.success,
        caption: o == null
            ? null
            : o.fromCache
                ? (o.lastRefresh == null ? 'Unavailable' : 'Last updated ${Fmt.relative(o.lastRefresh)}')
                : 'Live',
        onTap: () => context.go(Routes.employees),
      ),
      AppStatCard(
        key: const Key('stat-local'),
        label: 'Saved on this device',
        value: counts.total,
        icon: Icons.smartphone_rounded,
        accent: AppColors.peach,
        caption: '${counts.synced} synchronized',
        onTap: () => context.go(Routes.sync),
      ),
      AppStatCard(
        key: const Key('stat-awaiting'),
        label: 'Awaiting sync',
        value: counts.awaiting,
        icon: Icons.cloud_upload_outlined,
        accent: AppColors.info,
        caption: counts.failed > 0 ? '${counts.failed} failed' : 'Pending upload',
        onTap: () => context.go(Routes.sync),
      ),
      AppStatCard(
        key: const Key('stat-synced'),
        label: 'Synced from device',
        value: counts.synced,
        icon: Icons.task_alt_rounded,
        accent: AppColors.success,
        caption: 'Uploaded successfully',
        onTap: () => context.go(Routes.sync),
      ),
      if (admin) ...[
        _SourceCount(source: EnrollmentSource.photo, label: 'Photo uploads', icon: Icons.photo_outlined, accent: AppColors.peachSoft),
        _SourceCount(source: EnrollmentSource.capture, label: 'Camera captures', icon: Icons.videocam_outlined, accent: AppColors.info),
      ],
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? (admin ? 3 : 4) : 2;
      final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
      return Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          for (var i = 0; i < cards.length; i++) SizedBox(width: w, child: cards[i].entrance(context, index: i + 2)),
        ],
      );
    });
  }
}

class _SourceCount extends ConsumerWidget {
  const _SourceCount({required this.source, required this.label, required this.icon, required this.accent});
  final EnrollmentSource source;
  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(employeeCountBySourceProvider(source));
    return AppStatCard(
      label: label,
      value: v.valueOrNull,
      loading: v.isLoading && !v.hasValue,
      icon: icon,
      accent: accent,
      caption: v.valueOrNull == null && !v.isLoading ? 'Unavailable offline' : 'source = ${source.apiValue}',
      onTap: () => context.go(Routes.employees),
    );
  }
}

class _SyncStatusCard extends ConsumerWidget {
  const _SyncStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final counts = ref.watch(localCountsProvider);
    final status = ref.watch(connectionStatusProvider);
    final lastSync = ref.watch(lastSuccessfulSyncProvider);
    final running = ref.watch(syncControllerProvider.select((s) => s.running));
    final (color, icon) = networkStatusStyle(status.status);
    final headline = running
        ? 'Synchronizing…'
        : counts.awaiting == 0
            ? 'Everything is synchronized'
            : '${counts.awaiting} employee${counts.awaiting == 1 ? '' : 's'} waiting to sync';
    return AppCard(
      key: const Key('sync-status-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: Radii.smAll),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Synchronization', style: t.titleMedium),
                Text(headline, style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: Space.sm),
          InfoRow(label: 'Connection', value: status.status.label),
          InfoRow(label: 'Last successful sync', value: lastSync == null ? 'Never' : Fmt.relative(lastSync)),
          if (counts.failed > 0) InfoRow(label: 'Failed', value: '${counts.failed} (safe on this device)'),
          const SizedBox(height: Space.sm),
          Row(children: [
            const Expanded(child: SyncNowButton(expand: true, height: 44)),
            const SizedBox(width: Space.sm),
            AppIconButton(
              icon: Icons.open_in_new_rounded,
              tooltip: 'Open synchronization',
              onPressed: () => context.go(Routes.sync),
            ),
          ]),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.admin});
  final bool admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = [
      QuickActionTile(
        icon: Icons.person_add_alt_1_rounded,
        label: 'Register employee',
        caption: 'Photo + details',
        filled: true,
        onTap: () => context.go(Routes.enroll),
      ),
      QuickActionTile(
        icon: Icons.people_alt_outlined,
        label: 'Employees',
        caption: 'Search & browse',
        accent: AppColors.info,
        onTap: () => context.go(Routes.employees),
      ),
      QuickActionTile(
        icon: Icons.sync_rounded,
        label: 'Synchronization',
        caption: 'Pending & history',
        accent: AppColors.success,
        onTap: () => context.go(Routes.sync),
      ),
      if (admin)
        QuickActionTile(
          icon: Icons.bug_report_outlined,
          label: 'Diagnostics',
          caption: 'Network, data, tools',
          accent: AppColors.peachSoft,
          onTap: () => context.go(Routes.diagnostics),
        )
      else
        QuickActionTile(
          icon: Icons.wifi_tethering_rounded,
          label: 'Check connection',
          caption: 'Retry the server',
          accent: AppColors.peachSoft,
          onTap: () async {
            await ref.read(connectionStatusProvider.notifier).check();
            if (!context.mounted) return;
            final s = ref.read(connectionStatusProvider);
            showAppSnack(
              context,
              s.isOnline ? 'Connected to the server.' : 'Unable to reach the server. Your records are safe on this device.',
              type: s.isOnline ? SnackType.success : SnackType.warning,
            );
          },
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: 'Quick actions'),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 640 ? 4 : 2;
          final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
          return Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        }),
      ],
    );
  }
}

/// Registrations made on this device (any status), newest first.
class _RecentRegistrations extends ConsumerWidget {
  const _RecentRegistrations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(localEmployeesProvider).take(5).map((e) => EmployeeRecord(local: e)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Recent registrations',
          subtitle: 'Made on this device',
          actionLabel: 'View all',
          onAction: () => context.go(Routes.employees),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: items.isEmpty
              ? AppEmptyState(
                  compact: true,
                  icon: Icons.person_add_alt_outlined,
                  title: 'No registrations yet',
                  message: 'Employees you register here will appear with their sync status.',
                  actionLabel: 'Register an employee',
                  onAction: () => context.go(Routes.enroll),
                )
              : Column(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    EmployeeListTile(record: items[i]),
                    if (i < items.length - 1) Divider(color: context.palette.border, height: 8),
                  ],
                ]),
        ),
      ],
    );
  }
}

/// Admin: first page from the server (or its cached copy).
class _LatestOnServer extends ConsumerWidget {
  const _LatestOnServer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(serverOverviewProvider);
    final o = overview.valueOrNull;
    final linked = ref.watch(linkedLocalByServerIdProvider);
    final items = [
      for (final e in o?.latest ?? const <Employee>[]) EmployeeRecord(server: e, local: e.id == null ? null : linked[e.id]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Employee records on server',
          subtitle: o == null
              ? null
              : o.fromCache
                  ? 'Saved copy · last updated ${Fmt.relative(o.lastRefresh)}'
                  : 'First page, in server order',
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: o == null
              ? const Padding(padding: EdgeInsets.all(Space.xl), child: AppLoadingIndicator())
              : items.isEmpty
                  ? const AppEmptyState(compact: true, icon: Icons.cloud_queue_rounded, title: 'No server records', message: 'Nothing loaded from the server yet.')
                  : Column(children: [
                      for (var i = 0; i < items.length; i++) ...[
                        EmployeeListTile(record: items[i]),
                        if (i < items.length - 1) Divider(color: context.palette.border, height: 8),
                      ],
                    ]),
        ),
      ],
    );
  }
}

class _ActivityFeed extends ConsumerWidget {
  const _ActivityFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(activitiesProvider).take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Recent activity',
          subtitle: 'On this device',
          actionLabel: 'All',
          onAction: () => context.go(Routes.activity),
        ),
        AppCard(
          child: items.isEmpty
              ? const AppEmptyState(
                  compact: true,
                  icon: Icons.history_rounded,
                  title: 'No activity yet',
                  message: 'Registrations, syncs and environment changes made here will be listed.',
                )
              : Column(children: [
                  for (var i = 0; i < items.length; i++) ActivityTile(activity: items[i], isLast: i == items.length - 1),
                ]),
        ),
      ],
    );
  }
}
