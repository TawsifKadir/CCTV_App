import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
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
import '../../../core/widgets/enrolly_logo.dart';
import '../../authentication/providers/auth_controller.dart';
import '../../environments/presentation/providers/environment_providers.dart';
import '../../environments/presentation/widgets/environment_widgets.dart';
import '../../connectivity/app_features_provider.dart';
import '../../connectivity/connectivity_service.dart';
import '../../connectivity/connectivity_widgets.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../sync/data/sync_engine.dart';
import '../../sync/presentation/sync_providers.dart';
import '../../sync/presentation/sync_widgets.dart';
import '../widgets/settings_widgets.dart';

Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final ok = await showAppConfirmDialog(
    context,
    title: 'Sign out?',
    message: 'You will need to sign in again to register or view employees.',
    confirmLabel: 'Sign out',
    icon: Icons.logout_rounded,
  );
  if (ok) await ref.read(authControllerProvider.notifier).logout();
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showPrivacy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Photos & privacy'),
        content: const SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Text(
              'How Enrolly handles employee data:\n\n'
              '• Employee details and photographs are sent to the server. A copy is kept on this device so '
              'registrations are never lost while offline; you can clear it in Settings.\n\n'
              '• Face templates are created by the server — the app only captures or uploads the photograph. '
              'It performs no face detection or recognition itself.\n\n'
              '• Inform employees and obtain any consent your organisation requires before capturing a photograph.\n\n'
              '• Sign-in uses your organisation\'s server. With "Remember me", the session is kept in the '
              'device\'s secure storage; signing out removes it.\n\n'
              '• The app never logs photographs, passwords or request bodies.',
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _clearLocal(BuildContext context, WidgetRef ref) async {
    final counts = ref.read(localCountsProvider);
    final ok = await showAppConfirmDialog(
      context,
      title: 'Clear local data?',
      message: counts.awaiting > 0
          ? '${counts.awaiting} employee${counts.awaiting == 1 ? ' has' : 's have'} not reached the server yet and will be '
                'permanently lost. Employees already on the server are not affected.'
          : 'Employees and photos stored on this device will be removed. Employees on the server are not affected.',
      confirmLabel: counts.awaiting > 0 ? 'Delete anyway' : 'Clear',
      destructive: true,
      icon: Icons.delete_forever_outlined,
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
    final s = ref.watch(settingsProvider);
    final features = ref.watch(appFeaturesProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final op = ref.watch(authControllerProvider);
    final env = ref.watch(activeEnvironmentProvider);
    final build = ref.watch(buildEnvironmentProvider);
    final t = Theme.of(context).textTheme;

    final user = op?.operator;
    final profile = user == null
        ? const SizedBox.shrink()
        : AppCard(
            color: context.palette.nav,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.peach,
                  child: Text(Fmt.initials(user.fullName), style: t.titleLarge?.copyWith(color: Colors.white)),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: t.titleLarge?.copyWith(color: Colors.white)),
                      Text(user.email ?? user.username, style: t.bodySmall?.copyWith(color: Colors.white70)),
                      if (user.roles.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(user.roles.join(' · '), style: t.bodySmall?.copyWith(color: Colors.white54)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );

    final account = SettingsGroup(
      title: 'Account',
      children: [
        SettingsTile(icon: Icons.person_outline_rounded, title: 'Username', subtitle: user?.username ?? '—'),
        if (user?.email != null) SettingsTile(icon: Icons.mail_outline_rounded, title: 'Email', subtitle: user!.email),
        SettingsTile(icon: Icons.login_rounded, title: 'Signed in', subtitle: Fmt.dateTime(op?.createdAt)),
        SettingsTile(
          key: const Key('settings-sign-out'),
          icon: Icons.logout_rounded,
          title: 'Sign out',
          color: AppColors.error,
          onTap: () => confirmLogout(context, ref),
        ),
      ],
    );

    final appearance = SettingsGroup(
      title: 'Appearance',
      children: [
        SettingsTile(
          icon: Icons.palette_outlined,
          title: 'Theme',
          subtitle: switch (s.themeMode) {
            ThemeMode.system => 'Follows your device\'s light or dark appearance',
            ThemeMode.light => 'Always light',
            ThemeMode.dark => 'Always dark',
          },
          below: Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                key: const Key('theme-selector'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_outlined),
                    tooltip: 'System default',
                  ),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => notifier.update((x) => x.copyWith(themeMode: v.first)),
              ),
            ),
          ),
        ),
        SettingsSwitch(
          icon: Icons.animation_rounded,
          title: 'Reduce motion',
          subtitle: 'Minimise animations (the system setting is also respected)',
          value: s.reduceMotion,
          onChanged: (v) => notifier.update((x) => x.copyWith(reduceMotion: v)),
        ),
      ],
    );

    final counts = ref.watch(localCountsProvider);
    final connection = ref.watch(connectionStatusProvider);
    final lastSync = ref.watch(lastSuccessfulSyncProvider);
    final lastAttempt = ref.watch(lastSyncAttemptProvider);
    final photoBytes = ref.watch(localEmployeeRepositoryProvider).photoBytesTotal;

    final syncGroup = SettingsGroup(
      title: 'Synchronization',
      children: [
        SettingsSwitch(
          key: const Key('auto-sync-switch'),
          icon: Icons.sync_rounded,
          title: 'Automatic synchronization',
          subtitle: s.autoSync
              ? 'Upload pending employees as soon as the server is reachable'
              : 'Employees stay on this device until you tap Sync now',
          value: s.autoSync,
          color: AppColors.success,
          onChanged: (v) => notifier.update((x) => x.copyWith(autoSync: v)),
        ),
        SettingsSwitch(
          icon: Icons.wifi_rounded,
          title: 'Synchronize on Wi-Fi only',
          subtitle: 'Applies to automatic sync. Sync now always works.',
          value: s.syncOnWifiOnly,
          color: AppColors.info,
          onChanged: (v) => notifier.update((x) => x.copyWith(syncOnWifiOnly: v)),
        ),
        SettingsTile(
          icon: Icons.cloud_upload_outlined,
          title: 'Waiting to synchronize',
          subtitle: counts.awaiting == 0
              ? 'Nothing pending'
              : '${counts.awaiting} employee${counts.awaiting == 1 ? '' : 's'}${counts.failed > 0 ? ' · ${counts.failed} failed' : ''}',
          onTap: () => context.go(Routes.sync),
        ),
        if (counts.failed > 0)
          SettingsTile(
            icon: Icons.replay_rounded,
            title: 'Retry failed records',
            color: AppColors.error,
            onTap: () => runSyncNow(context, ref, selection: SyncSelection.failedOnly),
          ),
        SettingsTile(
          icon: Icons.history_rounded,
          title: 'Last successful synchronization',
          subtitle: lastSync == null ? 'Never' : Fmt.dateTime(lastSync),
        ),
        SettingsTile(
          icon: Icons.schedule_rounded,
          title: 'Last synchronization attempt',
          subtitle: lastAttempt == null ? 'Never' : Fmt.dateTime(lastAttempt),
        ),
      ],
    );

    final connectivityGroup = SettingsGroup(
      title: 'Connection',
      children: [
        SettingsTile(
          icon: networkStatusStyle(connection.status).$2,
          title: 'Status',
          subtitle: '${connection.status.label} · ${connection.device.label}',
          color: networkStatusStyle(connection.status).$1,
          trailing: const ConnectivityPill(compact: true),
        ),
        SettingsTile(
          icon: Icons.dns_outlined,
          title: 'Server',
          subtitle: switch (connection.backendReachable) {
            true =>
              'Reachable${connection.lastSuccessAt == null ? '' : ' · last connected ${Fmt.relative(connection.lastSuccessAt)}'}',
            false => 'Not reachable right now',
            null => 'Not checked yet',
          },
        ),
        SettingsTile(
          key: const Key('retry-connection-tile'),
          icon: Icons.wifi_tethering_rounded,
          title: 'Retry connection',
          onTap: () async {
            await ref.read(connectionStatusProvider.notifier).check();
            if (!context.mounted) return;
            final ok = ref.read(connectionStatusProvider).isOnline;
            showAppSnack(
              context,
              ok ? 'Connected to the server.' : 'Still unable to reach the server.',
              type: ok ? SnackType.success : SnackType.warning,
            );
          },
        ),
        if (features.connectionIntervalSetting)
          SettingsTile(
            icon: Icons.timer_outlined,
            title: 'Connection check interval',
            subtitle: 'Every ${s.connectionCheckSeconds}s while online · change in Diagnostics',
            color: AppColors.muted,
            onTap: () => context.push(Routes.diagnostics),
          ),
      ],
    );

    final dataGroup = SettingsGroup(
      title: 'Data on this device',
      children: [
        SettingsTile(
          icon: Icons.storage_rounded,
          title: 'Employees saved on this device',
          subtitle: '${counts.total} total · ${counts.synced} synchronized · ${counts.awaiting} pending',
          color: AppColors.info,
        ),
        SettingsTile(
          icon: Icons.photo_library_outlined,
          title: 'Photo storage',
          subtitle: Fmt.bytes(photoBytes),
          color: AppColors.info,
        ),
        SettingsTile(
          key: const Key('clear-local-data'),
          icon: Icons.delete_outline_rounded,
          title: 'Clear local data',
          subtitle: 'Remove employees and photos stored on this device',
          color: AppColors.error,
          onTap: () => _clearLocal(context, ref),
        ),
      ],
    );

    final backend = SettingsGroup(
      title: 'Backend (developer)',
      children: [
        SettingsTile(
          icon: Icons.dns_outlined,
          title: 'Environment configuration',
          subtitle: '${env.environmentName} · ${env.baseUrl}',
          color: environmentColor(env),
          trailing: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [ConnectionIndicator(), Icon(Icons.chevron_right_rounded)],
          ),
          onTap: () => context.push(Routes.environment),
        ),
        SettingsTile(
          icon: Icons.build_circle_outlined,
          title: 'Build environment',
          subtitle: build.runtimeSwitchingAllowed
              ? '${build.config.environmentName} (switchable at runtime)'
              : '${build.config.environmentName} (locked)',
          color: AppColors.info,
        ),
      ],
    );

    final capture = SettingsGroup(
      title: 'Camera',
      children: [
        SettingsSwitch(
          icon: Icons.camera_front_outlined,
          title: 'Use front camera by default',
          subtitle: s.preferFrontCamera ? 'Front-facing camera opens first' : 'Rear camera opens first',
          value: s.preferFrontCamera,
          onChanged: (v) => notifier.update((x) => x.copyWith(preferFrontCamera: v)),
        ),
      ],
    );

    final privacy = SettingsGroup(
      title: 'Privacy',
      children: [
        SettingsTile(
          icon: Icons.privacy_tip_outlined,
          title: 'Photos & privacy',
          subtitle: 'How photographs and personal data are handled',
          onTap: () => _showPrivacy(context),
        ),
      ],
    );

    final about = AppCard(
      child: Column(
        children: [
          const EnrollyLogo(size: 40, showTagline: true),
          const SizedBox(height: Space.md),
          Text('Version ${AppConstants.version}', style: t.bodySmall),
          const SizedBox(height: Space.md),
          AppSecondaryButton(
            label: 'Sign out',
            icon: Icons.logout_rounded,
            variant: AppSecondaryVariant.danger,
            onPressed: () => confirmLogout(context, ref),
          ),
        ],
      ),
    );

    const gap = SizedBox(height: Space.lg);
    // Client (production) builds: no backend URLs, environments or tools.
    final admin = features.adminMode;
    final diagnostics = SettingsGroup(
      title: 'Developer',
      children: [
        SettingsTile(
          icon: Icons.bug_report_outlined,
          title: 'Diagnostics',
          subtitle: 'Network log, sync log, local database, test data',
          color: AppColors.muted,
          onTap: () => context.push(Routes.diagnostics),
        ),
      ],
    );
    final left = [profile, gap, account, gap, appearance, gap, capture, gap, privacy];
    final right = [
      syncGroup,
      gap,
      connectivityGroup,
      gap,
      dataGroup,
      gap,
      if (admin) ...[backend, gap, diagnostics, gap],
      about,
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AppPage(
          maxWidth: 1180,
          children: [
            AppPageHeader(
              title: 'Settings',
              subtitle: admin
                  ? 'Appearance, sync, backend and developer tools.'
                  : 'Appearance, synchronization and account.',
            ),
            if (context.screenWidth >= 1000)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
                  ),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
                  ),
                ],
              )
            else
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, gap, ...right]),
          ],
        ),
      ),
    );
  }
}
