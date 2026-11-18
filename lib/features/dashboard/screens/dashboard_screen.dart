import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/motion.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_layout.dart';
import '../../../core/widgets/brand_surface.dart';
import '../../authentication/domain/permissions.dart';
import '../../authentication/providers/auth_controller.dart';
import '../../connectivity/connectivity_service.dart';
import '../../employees/data/models/employee_record.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../employees/presentation/widgets/employee_list_widgets.dart';

/// Minimal dashboard: the two primary tasks, three real figures and the
/// latest registrations. Connection problems are shown by the shell's status
/// bar only when they occur.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    final perms = ref.watch(permissionsProvider);
    final t = Theme.of(context).textTheme;
    final name = session?.operator.fullName ?? '';

    final mobile = context.isMobile;
    final hero = BrandSurface(
      borderRadius: BorderRadius.circular(Radii.xl + 4),
      child: Padding(
        padding: EdgeInsets.all(mobile ? Space.md : Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          '${perms.roleLabel} · ${Fmt.date(DateTime.now())}',
                          style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Welcome, $name',
                        key: const Key('dashboard-welcome'),
                        style: (mobile ? t.headlineSmall : t.headlineMedium)?.copyWith(color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!mobile) const SizedBox(height: 4),
                      if (!mobile)
                        Text(
                          'Here is today\'s enrollment overview.',
                          style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                        ),
                    ],
                  ),
                ),
                if (mobile)
                  AppIconButton(
                    icon: Icons.person_outline_rounded,
                    tooltip: 'Profile & settings',
                    background: Colors.white.withValues(alpha: 0.16),
                    foreground: Colors.white,
                    onPressed: () => context.go(Routes.settings),
                  ),
              ],
            ),
            SizedBox(height: mobile ? Space.md : Space.lg),
            const _Stats(),
          ],
        ),
      ),
    );

    const gap = SizedBox(height: Space.lg);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await ref.read(connectionStatusProvider.notifier).check();
            ref.read(employeeRefresherProvider)();
          },
          child: AppPage(
            maxWidth: 1080,
            children: [
              hero.entrance(context),
              gap,
              const _PrimaryActions().entrance(context, index: 1),
              gap,
              const _RecentRegistrations().entrance(context, index: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions();

  @override
  Widget build(BuildContext context) {
    const register = _ActionTile(
      key: Key('action-register'),
      icon: Icons.person_add_alt_1_rounded,
      title: 'Register New Employee',
      subtitle: 'Take a photo and enter the details',
      route: Routes.enroll,
      filled: true,
    );
    const view = _ActionTile(
      key: Key('action-employees'),
      icon: Icons.groups_2_outlined,
      title: 'View Employees',
      subtitle: 'Search the employee directory',
      route: Routes.employees,
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 620
          ? const IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: register),
                  SizedBox(width: Space.md),
                  Expanded(child: view),
                ],
              ),
            )
          : const Column(
              children: [
                register,
                SizedBox(height: Space.md),
                view,
              ],
            ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.filled = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      onTap: () => context.go(route),
      border: true,
      padding: const EdgeInsets.all(Space.lg - 4),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: filled ? AppColors.actionGradient : null,
              color: filled ? null : p.accentTint,
              borderRadius: BorderRadius.circular(Radii.lg),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: filled ? Colors.white : p.accent, size: 27),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: t.bodySmall?.copyWith(color: p.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: filled ? AppColors.primary : p.backgroundAlt, shape: BoxShape.circle),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: filled ? Colors.white : p.text),
          ),
        ],
      ),
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(serverOverviewProvider);
    final o = overview.valueOrNull;
    final counts = ref.watch(localCountsProvider);
    final stats = [
      _Stat(
        key: const Key('stat-total'),
        label: 'Total employees',
        shortLabel: 'Total',
        value: o?.total,
        loading: overview.isLoading && o == null,
        caption: o == null
            ? null
            : o.fromCache
            ? (o.lastRefresh == null ? 'Unavailable offline' : 'As of ${Fmt.relative(o.lastRefresh)}')
            : 'On the server',
        icon: Icons.groups_2_outlined,
        onTap: () => context.go(Routes.employees),
      ),
      _Stat(
        key: const Key('stat-pending'),
        label: 'Pending registrations',
        shortLabel: 'Pending',
        value: counts.awaiting,
        caption: counts.failed > 0 ? '${counts.failed} need attention' : 'Waiting to upload',
        accent: counts.failed > 0 ? const Color(0xFFFF9B9B) : const Color(0xFFFFD08A),
        icon: Icons.cloud_upload_outlined,
        onTap: () => context.go(Routes.sync),
      ),
      _Stat(
        key: const Key('stat-synced'),
        label: 'Synchronized',
        shortLabel: 'Synced',
        value: counts.synced,
        caption: 'Uploaded from this device',
        accent: const Color(0xFF8FE3BE),
        icon: Icons.cloud_done_outlined,
        onTap: () => context.go(Routes.sync),
      ),
    ];
    // One row on every width; phones get short labels and no captions so
    // nothing wraps or truncates.
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 560;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) SizedBox(width: compact ? Space.xs : Space.md),
                Expanded(child: stats[i].copyWith(compact: compact)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.label,
    required this.shortLabel,
    this.compact = false,
    required this.value,
    this.caption,
    this.loading = false,
    this.accent = AppColors.navAccent,
    this.icon = Icons.insights_rounded,
    this.onTap,
  });

  final IconData icon;

  final String label;
  final String shortLabel;
  final bool compact;

  _Stat copyWith({required bool compact}) => _Stat(
    key: key,
    label: label,
    shortLabel: shortLabel,
    compact: compact,
    value: value,
    caption: caption,
    loading: loading,
    accent: accent,
    icon: icon,
    onTap: onTap,
  );

  /// `null` = unknown (shown as "—", never 0).
  final int? value;
  final String? caption;
  final bool loading;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(Radii.lg);
    // Glass tile on the brand hero.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? Space.sm : Space.md, vertical: Space.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Phones: a coloured dot instead of the icon so the label fits.
                  if (compact)
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    )
                  else
                    Icon(icon, size: 17, color: accent),
                  SizedBox(width: compact ? 5 : 6),
                  Expanded(
                    child: compact
                        // Short labels shrink a little rather than truncate on narrow phones.
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              shortLabel,
                              style: t.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
                              maxLines: 1,
                            ),
                          )
                        : Text(
                            label,
                            style: t.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              else
                Text(
                  value == null ? '—' : Fmt.number(value!),
                  style: (compact ? t.headlineSmall : t.headlineMedium)?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (caption != null && !compact)
                Text(
                  caption!,
                  style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Latest registrations with photos: this device's unsynced records first,
/// then the newest server records (linked records are not duplicated).
class _RecentRegistrations extends ConsumerWidget {
  const _RecentRegistrations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locals = ref.watch(localEmployeesProvider).where((e) => e.isUnsynced).map((e) => EmployeeRecord(local: e));
    final overview = ref.watch(serverOverviewProvider).valueOrNull;
    final linked = ref.watch(linkedLocalByServerIdProvider);
    final server = [
      for (final e in overview?.latest ?? const [])
        EmployeeRecord(server: e, local: e.id == null ? null : linked[e.id]),
    ];
    final items = [...locals, ...server].take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Recent registrations',
          subtitle: overview?.fromCache == true ? 'Saved copy · may be out of date' : null,
          actionLabel: 'View all',
          onAction: () => context.go(Routes.employees),
        ),
        AppCard(
          border: true,
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: items.isEmpty
              ? AppEmptyState(
                  compact: true,
                  icon: Icons.person_add_alt_outlined,
                  title: 'No registrations yet',
                  message: 'Registered employees will appear here.',
                  actionLabel: 'Register an employee',
                  onAction: () => context.go(Routes.enroll),
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      EmployeeListTile(record: items[i]),
                      if (i < items.length - 1) Divider(color: context.palette.border, height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
