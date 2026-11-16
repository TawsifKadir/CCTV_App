import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/services/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_cards.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_layout.dart';
import '../connectivity/connectivity_service.dart';
import '../employees/data/models/local_employee.dart';
import '../employees/presentation/providers/employee_providers.dart';
import '../environments/presentation/providers/environment_providers.dart';
import '../registration/domain/employee_photo.dart';
import '../registration/domain/employee_registration.dart';
import '../sync/presentation/sync_providers.dart';
import 'data/network_log.dart';

/// Admin-only diagnostics. This screen's route is only registered in admin
/// builds (see app_router.dart); client builds cannot reach it.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = context.pagePadding;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, context.isMobile ? Space.md : Space.xl, pad, 0),
                child: const AppPageHeader(title: 'Diagnostics', subtitle: 'Developer tools — not available in production builds.'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: AppColors.peach,
                  labelColor: AppColors.peach,
                  tabs: [Tab(text: 'Network'), Tab(text: 'Sync log'), Tab(text: 'Local data'), Tab(text: 'Tools')],
                ),
              ),
              const Expanded(
                child: TabBarView(children: [_NetworkTab(), _SyncLogTab(), _DataTab(), _ToolsTab()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

EdgeInsets _tabPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(context.pagePadding, Space.md, context.pagePadding, context.useSidebar ? Space.xl : 120);

class _NetworkTab extends ConsumerWidget {
  const _NetworkTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(networkLogProvider);
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder<List<NetworkLogEntry>>(
      valueListenable: log,
      builder: (context, entries, _) => ListView(
        padding: _tabPadding(context),
        children: [
          Row(children: [
            Expanded(child: Text('${entries.length} recent requests (bodies of uploaded photos are never kept)', style: t.bodySmall)),
            TextButton(onPressed: log.clear, child: const Text('Clear')),
          ]),
          if (entries.isEmpty)
            const AppEmptyState(compact: true, icon: Icons.http_rounded, title: 'No requests yet', message: 'API calls will appear here.'),
          for (final e in entries)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ExpansionTile(
                leading: Text(e.method, style: t.labelLarge?.copyWith(color: AppColors.peach)),
                title: Text(e.url, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                subtitle: Text(
                  '${e.status ?? e.error ?? '—'} · ${e.durationMs ?? '?'} ms · ${Fmt.time(e.startedAt)}',
                  style: t.labelSmall?.copyWith(color: e.ok ? AppColors.success : AppColors.error),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.requestSummary != null) ...[
                    Text('Request', style: t.labelMedium),
                    SelectableText(e.requestSummary!, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
                    const SizedBox(height: Space.xs),
                  ],
                  Text('Response', style: t.labelMedium),
                  SelectableText(e.responsePreview ?? '(empty)', style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SyncLogTab extends ConsumerWidget {
  const _SyncLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(syncHistoryProvider);
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: _tabPadding(context),
      children: [
        if (runs.isEmpty)
          const AppEmptyState(compact: true, icon: Icons.history_rounded, title: 'No sync runs', message: 'Runs and per-record outcomes appear here.'),
        for (final r in runs)
          AppCard(
            padding: const EdgeInsets.all(Space.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.resultLabel} · ${r.trigger.label} · ${Fmt.dateTime(r.startedAt)}', style: t.labelLarge),
              Text(
                'attempted ${r.attempted}, uploaded ${r.uploaded}, already ${r.alreadySynced}, failed ${r.failed}, '
                'uncertain ${r.uncertain}${r.aborted ? ', aborted' : ''} · ${r.duration.inMilliseconds} ms',
                style: t.bodySmall,
              ),
              for (final rec in r.records)
                Text('• ${rec.name} [${rec.localId.substring(0, 8)}]: ${rec.outcome}${rec.detail == null ? '' : ' — ${rec.detail}'}',
                    style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
            ]),
          ),
      ].expand((w) => [w, const SizedBox(height: Space.sm)]).toList(),
    );
  }
}

class _DataTab extends ConsumerWidget {
  const _DataTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locals = ref.watch(localEmployeesProvider);
    final counts = ref.watch(localCountsProvider);
    final cache = ref.watch(serverEmployeeCacheProvider);
    final repo = ref.watch(localEmployeeRepositoryProvider);
    final env = ref.watch(activeEnvironmentProvider);
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: _tabPadding(context),
      children: [
        AppCard(
          child: Column(children: [
            InfoRow(label: 'Environment', value: '${env.environmentId} · ${env.baseUrl}'),
            InfoRow(label: 'Local records', value: '${counts.total} (synced ${counts.synced}, awaiting ${counts.awaiting})'),
            InfoRow(label: 'Local photos', value: Fmt.bytes(repo.photoBytesTotal)),
            InfoRow(label: 'Cached server records', value: '${cache.count}'),
            InfoRow(label: 'Cache last refreshed', value: Fmt.dateTime(cache.lastRefresh)),
            InfoRow(label: 'Storage', value: 'Hive: app files (mobile) / IndexedDB (web)'),
          ]),
        ),
        const SizedBox(height: Space.md),
        Text('Local records', style: t.titleMedium),
        const SizedBox(height: Space.xs),
        for (final e in locals)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ExpansionTile(
              title: Text(e.name, style: t.labelLarge),
              subtitle: Text('${e.syncStatus.code}${e.needsReconciliation ? ' · NEEDS_REVIEW' : ''}${e.isTestData ? ' · TEST' : ''}',
                  style: t.labelSmall),
              childrenPadding: const EdgeInsets.all(Space.md),
              children: [
                SelectableText(const JsonEncoder.withIndent('  ').convert(e.toJson()),
                    style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
              ],
            ),
          ),
      ],
    );
  }
}

class _ToolsTab extends ConsumerWidget {
  const _ToolsTab();

  /// Simple generated image (never a real person, never the brand photo).
  static Uint8List _testPhoto(int seed) {
    final image = img.Image(width: 240, height: 240);
    img.fill(image, color: img.ColorRgb8(60 + seed * 40 % 180, 120, 200 - seed * 30 % 150));
    return Uint8List.fromList(img.encodePng(image));
  }

  Future<void> _createTestRecords(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(localEmployeeRepositoryProvider);
    final n = repo.all().where((e) => e.isTestData).length;
    for (var i = 0; i < 3; i++) {
      await repo.create(
        EmployeeRegistration(
          name: 'Test Employee ${n + i + 1}',
          dateOfBirth: DateTime(1990, 1, 1 + i),
          designation: 'Test data',
          photo: EmployeePhoto.fromBytes(_testPhoto(n + i), origin: PhotoOrigin.upload),
        ),
        status: SyncStatus.pendingSync,
        isTestData: true,
      );
    }
    if (context.mounted) {
      showAppSnack(context, 'Created 3 test records. They are never uploaded; syncing them shows the failure flow.',
          type: SnackType.success);
    }
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final counts = ref.read(localCountsProvider);
    final ok = await showAppConfirmDialog(
      context,
      title: 'Clear all local employee data?',
      message: 'Deletes ${counts.total} local records (${counts.awaiting} not yet on the server — they will be lost), '
          'their photos, cached server records and sync history for this environment.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(localEmployeeRepositoryProvider).clear();
    await ref.read(serverEmployeeCacheProvider).clear();
    await ref.read(syncHistoryRepositoryProvider).clear();
    ref.read(employeeRefresherProvider)();
    if (context.mounted) showAppSnack(context, 'Local data cleared.', type: SnackType.success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final status = ref.watch(connectionStatusProvider);
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: _tabPadding(context),
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Connection', style: t.titleMedium),
            InfoRow(label: 'Status', value: '${status.status.label} (device: ${status.device.label})'),
            InfoRow(label: 'Consecutive failures', value: '${status.failures}'),
            InfoRow(label: 'Last error', value: status.message),
            const SizedBox(height: Space.sm),
            Text('Check interval while online: ${settings.connectionCheckSeconds}s', style: t.labelMedium),
            Slider(
              key: const Key('interval-slider'),
              value: settings.connectionCheckSeconds.toDouble(),
              min: 10,
              max: 300,
              divisions: 29,
              label: '${settings.connectionCheckSeconds}s',
              onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(connectionCheckSeconds: v.round())),
            ),
            AppSecondaryButton(
              label: 'Check now',
              icon: Icons.wifi_tethering_rounded,
              height: 44,
              loading: status.checking,
              onPressed: () => ref.read(connectionStatusProvider.notifier).check(),
            ),
          ]),
        ),
        const SizedBox(height: Space.md),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Test data', style: t.titleMedium),
            Text('Test records stay on this device and are never sent to the server.', style: t.bodySmall),
            const SizedBox(height: Space.sm),
            AppSecondaryButton(
              key: const Key('create-test-records'),
              label: 'Create 3 pending test records',
              icon: Icons.science_outlined,
              height: 44,
              onPressed: () => _createTestRecords(context, ref),
            ),
            const SizedBox(height: Space.xs),
            AppSecondaryButton(
              label: 'Reset failed records to pending',
              icon: Icons.restart_alt_rounded,
              height: 44,
              onPressed: () async {
                final repo = ref.read(localEmployeeRepositoryProvider);
                for (final e in repo.all().where((e) => e.syncStatus == SyncStatus.failed)) {
                  await repo.update(e.localId, (x) => x.copyWith(
                        syncStatus: SyncStatus.pendingSync,
                        permanentFailure: false,
                        nextRetryAt: () => null,
                      ));
                }
              },
            ),
            const SizedBox(height: Space.xs),
            AppSecondaryButton(
              label: 'Clear cached server records',
              icon: Icons.cleaning_services_outlined,
              height: 44,
              onPressed: () async {
                await ref.read(serverEmployeeCacheProvider).clear();
                ref.read(employeeRefresherProvider)();
              },
            ),
            const SizedBox(height: Space.xs),
            AppSecondaryButton(
              label: 'Clear all local employee data',
              icon: Icons.delete_forever_outlined,
              variant: AppSecondaryVariant.danger,
              height: 44,
              onPressed: () => _clearAll(context, ref),
            ),
          ]),
        ),
      ],
    );
  }
}
