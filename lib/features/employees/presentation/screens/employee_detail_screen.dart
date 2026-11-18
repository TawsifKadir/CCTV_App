import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/motion.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_cards.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_layout.dart';
import '../../../authentication/domain/permissions.dart';
import '../../../connectivity/app_features_provider.dart';
import '../../../environments/presentation/providers/environment_providers.dart';
import '../../../sync/data/sync_engine.dart';
import '../../../sync/presentation/sync_providers.dart';
import '../../../sync/presentation/sync_widgets.dart';
import '../../data/models/employee_record.dart';
import '../../data/models/local_employee.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_avatar.dart';
import '../widgets/employee_list_widgets.dart';

/// Read-only employee profile with its storage and synchronization state.
///
/// The backend has no get-by-id, update or delete endpoints, so there are no
/// edit/delete actions. The profile is found from the current list, the
/// device records or the cached server records (survives a browser refresh).
class EmployeeDetailScreen extends ConsumerStatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeKey, this.initial});

  final String employeeKey;
  final EmployeeRecord? initial;

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  bool _busy = false;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.employees);
    }
  }

  Future<void> _sync(LocalEmployee e) async {
    setState(() => _busy = true);
    final (start, result) = await ref.read(syncControllerProvider.notifier).syncOne(e.localId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (start == SyncStart.offline) {
      await showOfflineSyncDialog(context, ref);
      return;
    }
    final msg = switch (result?.outcome) {
      UploadOutcome.uploaded => ('${e.name} is now on the server.', SnackType.success),
      UploadOutcome.alreadySynced => ('${e.name} was already on the server and has been linked.', SnackType.success),
      UploadOutcome.uncertain => (
        'The server didn\'t confirm the upload. It will be checked before retrying.',
        SnackType.warning,
      ),
      UploadOutcome.skipped => ('This employee is already being uploaded.', SnackType.info),
      _ => (result?.message ?? 'Synchronization failed. The employee is still saved on this device.', SnackType.error),
    };
    showAppSnack(context, msg.$1, type: msg.$2);
  }

  @override
  Widget build(BuildContext context) {
    final features = ref.watch(appFeaturesProvider);
    final perms = ref.watch(permissionsProvider);
    final env = ref.watch(activeEnvironmentProvider);
    // Prefer the live record (status changes while the page is open).
    final record = ref.watch(employeeRecordProvider(widget.employeeKey)) ?? widget.initial;
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final back = AppIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: _back);

    if (record == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: AppEmptyState(
            icon: Icons.person_search_outlined,
            title: 'Employee not found',
            message: 'This employee isn\'t on this device or in the loaded records. Open it from the employee list.',
            actionLabel: 'Go to employees',
            onAction: () => context.go(Routes.employees),
          ),
        ),
      );
    }

    final e = record.view;
    final local = record.local;
    final photoSize = context.isMobile ? 168.0 : 220.0;
    final hero = AppCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(Radii.xl + 6)),
            child: EmployeeAvatar(record: record, size: photoSize, radius: Radii.xl, heroTag: 'emp-${record.key}'),
          ),
          const SizedBox(height: Space.md),
          Text(e.name, style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            e.designation ?? '—',
            style: t.bodyLarge?.copyWith(color: p.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              SyncStatusBadge(record: record, dense: false),
              if (e.employeeNo != null)
                AppPill(label: Fmt.employeeNo(e.employeeNo), color: AppColors.primary, showDot: false),
              if (record.isOnServer) SourcePill(employee: e, dense: false),
              if (features.environmentIndicator)
                AppPill(label: env.environmentName, color: AppColors.info, icon: Icons.dns_outlined),
            ],
          ),
        ],
      ),
    );

    final identity = _Section(
      title: 'Identity',
      children: [
        InfoRow(icon: Icons.badge_outlined, label: 'Employee number', value: Fmt.employeeNo(e.employeeNo)),
        InfoRow(icon: Icons.tag_rounded, label: 'Server employee ID', value: e.id?.toString() ?? 'Not assigned yet'),
        InfoRow(icon: Icons.person_outline_rounded, label: 'Full name', value: e.name),
        InfoRow(icon: Icons.cake_outlined, label: 'Date of birth', value: Fmt.date(e.dateOfBirth)),
        InfoRow(icon: Icons.work_outline_rounded, label: 'Designation', value: e.designation),
      ],
    );

    final storage = _Section(
      title: 'Storage & synchronization',
      children: [
        if (local != null && local.isUnsynced)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: AppBanner(
              key: const Key('not-uploaded-banner'),
              type: (local.syncStatus == SyncStatus.reconciliationRequired) || local.syncStatus == SyncStatus.failed
                  ? SnackType.warning
                  : SnackType.info,
              title: (local.syncStatus == SyncStatus.reconciliationRequired) ? 'Needs review' : 'Not yet uploaded',
              message: (local.syncStatus == SyncStatus.reconciliationRequired)
                  ? 'The app could not confirm whether the server saved this employee. Before uploading again it '
                        'will search the server for a matching record, so the employee isn\'t registered twice.'
                  : 'This employee is saved on this device and has not reached the server yet. '
                        'It will be uploaded when you synchronize.',
            ),
          ),
        InfoRow(
          icon: Icons.storage_rounded,
          label: 'Stored',
          value: switch ((record.isOnServer, local != null)) {
            (true, true) => 'On the server and on this device',
            (true, false) => 'On the server',
            (false, _) => 'On this device only',
          },
        ),
        InfoRow(icon: Icons.sync_rounded, label: 'Sync status', value: record.statusLabel),
        if (local != null) ...[
          InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Last sync attempt',
            value: local.lastSyncAttempt == null ? 'Never' : Fmt.dateTime(local.lastSyncAttempt),
          ),
          InfoRow(
            icon: Icons.cloud_done_outlined,
            label: 'Last successful sync',
            value: local.lastSuccessfulSync == null ? '—' : Fmt.dateTime(local.lastSuccessfulSync),
          ),
          InfoRow(icon: Icons.fingerprint_rounded, label: 'Local record ID', value: local.localId),
          if (local.syncError != null)
            InfoRow(icon: Icons.error_outline_rounded, label: 'Last error', value: local.syncError),
          if (local.serverWarning != null)
            InfoRow(icon: Icons.hourglass_top_rounded, label: 'Server note', value: local.serverWarning),
        ],
        if (local != null && local.isUnsynced && !local.isTestData) ...[
          const SizedBox(height: Space.sm),
          AppPrimaryButton(
            key: const Key('sync-one'),
            label: (local.syncStatus == SyncStatus.reconciliationRequired)
                ? 'Check server & sync'
                : 'Sync this employee',
            icon: Icons.cloud_upload_outlined,
            height: 46,
            loading: _busy || local.syncStatus == SyncStatus.syncing,
            onPressed: _busy ? null : () => _sync(local),
          ),
        ],
      ],
    );

    final enrollment = _Section(
      title: 'Enrollment',
      children: [
        _CopyRow(label: 'Template ID', value: e.templateId),
        InfoRow(
          icon: Icons.memory_rounded,
          label: 'Template size',
          value: e.templateBytes == null ? null : '${Fmt.number(e.templateBytes!)} bytes',
        ),
        InfoRow(
          icon: Icons.event_available_outlined,
          label: record.isOnServer ? 'Enrolled at' : 'Registered on device',
          value: Fmt.dateTime(e.enrolledAt),
        ),
        InfoRow(
          icon: Icons.input_rounded,
          label: 'Enrollment source',
          value: record.isOnServer ? e.sourceLabel : 'Assigned by the server after upload',
        ),
      ],
    );

    // Admin builds only: raw stored data for debugging.
    final raw = !features.rawRecordDetails
        ? null
        : _Section(
            title: 'Raw record (admin)',
            children: [
              SelectableText(
                const JsonEncoder.withIndent('  ').convert({
                  if (record.server != null) 'server': record.server!.toJson(),
                  if (local != null) 'local': local.toJson(),
                }),
                key: const Key('raw-record'),
                style: t.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          );

    final wide = context.screenWidth >= 1000;
    final rightColumn = [
      storage.entrance(context, index: 1),
      const SizedBox(height: Space.lg),
      identity.entrance(context, index: 2),
      const SizedBox(height: Space.lg),
      enrollment.entrance(context, index: 3),
      if (raw != null) ...[const SizedBox(height: Space.lg), raw],
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AppPage(
          maxWidth: 1100,
          children: [
            AppPageHeader(
              title: 'Employee profile',
              subtitle: record.isOnServer ? 'On the server' : 'Saved on this device',
              leading: back,
              // Administrators only (and re-checked in each handler). Phones
              // use one overflow menu so the title never wraps.
              actions: [
                if ((perms.canEditEmployees || perms.canDeleteEmployees) && record.isOnServer && context.isMobile)
                  PopupMenuButton<String>(
                    key: const Key('employee-actions'),
                    tooltip: 'Employee actions',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) =>
                        v == 'edit' ? requestEditEmployee(context, perms) : requestDeleteEmployee(context, perms),
                    itemBuilder: (_) => [
                      if (perms.canEditEmployees) const PopupMenuItem(value: 'edit', child: Text('Edit employee')),
                      if (perms.canDeleteEmployees)
                        const PopupMenuItem(value: 'delete', child: Text('Delete employee')),
                    ],
                  ),
                if (perms.canEditEmployees && record.isOnServer && !context.isMobile)
                  AppIconButton(
                    key: const Key('employee-edit'),
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit employee',
                    onPressed: () => requestEditEmployee(context, perms),
                  ),
                if (perms.canDeleteEmployees && record.isOnServer && !context.isMobile)
                  AppIconButton(
                    key: const Key('employee-delete'),
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete employee',
                    foreground: AppColors.error,
                    onPressed: () => requestDeleteEmployee(context, perms),
                  ),
              ],
            ),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: hero.entrance(context)),
                  const SizedBox(width: Space.lg),
                  Expanded(flex: 6, child: Column(children: rightColumn)),
                ],
              )
            else ...[
              hero.entrance(context),
              const SizedBox(height: Space.lg),
              ...rightColumn,
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          ...children,
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Icon(Icons.fingerprint_rounded, size: 18, color: p.textMuted),
          const SizedBox(width: Space.sm),
          Text(label, style: t.bodyMedium?.copyWith(color: p.textMuted)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: SelectableText(
              value ?? '—',
              textAlign: TextAlign.right,
              maxLines: 1,
              style: t.bodySmall?.copyWith(fontFamily: 'monospace', color: p.text),
            ),
          ),
          if (value != null)
            IconButton(
              tooltip: 'Copy template ID',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value!));
                showAppSnack(context, 'Template ID copied');
              },
            ),
        ],
      ),
    );
  }
}
