import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/environment_config.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_cards.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_layout.dart';
import '../../../connectivity/connectivity_service.dart';
import '../providers/environment_providers.dart';
import '../widgets/environment_widgets.dart';

/// Shows the build-time environment, the active (runtime) environment, the
/// backend connection, and lets non-production builds switch servers.
class EnvironmentScreen extends ConsumerWidget {
  const EnvironmentScreen({super.key});

  Future<void> _select(BuildContext context, WidgetRef ref, EnvironmentConfig env) async {
    if (env.isProduction) {
      final ok = await showAppConfirmDialog(
        context,
        title: 'Switch to Production?',
        message: 'Registrations will be saved to the live production backend (${env.baseUrl}). '
            'Only continue if you intend to work with real employee records.',
        confirmLabel: 'Use Production',
        destructive: true,
        icon: Icons.warning_amber_rounded,
      );
      if (!ok) return;
    }
    try {
      await ref.read(activeEnvironmentProvider.notifier).select(env.environmentId);
      if (!context.mounted) return;
      showAppSnack(context, 'Now using ${env.environmentName}.', type: SnackType.success);
      await ref.read(connectionStatusProvider.notifier).check();
    } catch (e) {
      if (context.mounted) showAppSnack(context, 'Could not switch environment.', type: SnackType.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final build = ref.watch(buildEnvironmentProvider);
    final active = ref.watch(activeEnvironmentProvider);
    final status = ref.watch(connectionStatusProvider);
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    final back = context.canPop()
        ? AppIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => context.pop())
        : null;

    final current = AppCard(
      color: p.nav,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Active backend',
                    style: t.titleMedium?.copyWith(color: Colors.white70), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: Space.xs),
              const EnvironmentBadge(onDark: true),
            ],
          ),
          const SizedBox(height: Space.md),
          SelectableText(
            active.baseUrl ?? '—',
            key: const Key('active-base-url'),
            style: t.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text('API base: ${active.apiBaseUrl}', style: t.bodySmall?.copyWith(color: Colors.white60)),
          if (active.notes != null) ...[
            const SizedBox(height: Space.sm),
            Text(active.notes!, style: t.bodySmall?.copyWith(color: Colors.white70)),
          ],
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const ConnectionIndicator(onDark: true),
              Text(
                status.lastSuccessAt == null ? 'No successful connection yet' : 'Last successful call: ${Fmt.dateTime(status.lastSuccessAt)}',
                style: t.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
          ),
          if (!status.isOnline && status.message != null) ...[
            const SizedBox(height: Space.sm),
            Text(status.message!, style: t.bodySmall?.copyWith(color: const Color(0xFFF2B8B3))),
          ],
          const SizedBox(height: Space.md),
          AppPrimaryButton(
            key: const Key('test-connection'),
            label: 'Test connection',
            icon: Icons.wifi_tethering_rounded,
            expand: false,
            height: 46,
            loading: status.checking,
            onPressed: () => ref.read(connectionStatusProvider.notifier).check(),
          ),
        ],
      ),
    );

    final buildInfo = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Build configuration', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          InfoRow(icon: Icons.build_circle_outlined, label: 'Build environment', value: build.config.environmentName),
          InfoRow(icon: Icons.input_rounded, label: 'Selected by', value: build.source.label),
          InfoRow(
            icon: Icons.swap_horiz_rounded,
            label: 'Runtime switching',
            value: build.runtimeSwitchingAllowed ? 'Allowed' : 'Locked to ${build.config.environmentName}',
          ),
          if (!build.runtimeSwitchingAllowed) ...[
            const SizedBox(height: Space.sm),
            const AppBanner(
              type: SnackType.info,
              message: 'Production builds always use the production backend and cannot be switched.',
            ),
          ],
        ],
      ),
    );

    final unconfigured = build.unconfigured();
    final selector = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: 'Environments', subtitle: 'Choose which backend this app talks to'),
        for (final env in build.available) ...[
          _EnvOption(
            env: env,
            selected: env == active,
            enabled: build.runtimeSwitchingAllowed,
            onTap: () => _select(context, ref, env),
          ),
          const SizedBox(height: Space.sm),
        ],
        for (final env in unconfigured) ...[
          _EnvOption(env: env, selected: false, enabled: false, onTap: null),
          const SizedBox(height: Space.sm),
        ],
        const SizedBox(height: Space.xs),
        Text(
          'Add or change backend URLs in lib/core/config/environment_registry.dart. '
          'Unconfigured environments cannot be selected.',
          style: t.bodySmall,
        ),
      ],
    );

    final wide = context.screenWidth >= 1000;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AppPage(
          maxWidth: 1100,
          children: [
            AppPageHeader(
              title: 'Environment',
              subtitle: 'Backend server, connection and build configuration',
              leading: back,
              actions: [
                if (!context.isMobile && !context.canPop())
                  AppSecondaryButton(
                    label: 'Settings',
                    icon: Icons.tune_outlined,
                    expand: false,
                    height: 46,
                    onPressed: () => context.go(Routes.settings),
                  ),
              ],
            ),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: [current, const SizedBox(height: Space.lg), buildInfo])),
                  const SizedBox(width: Space.lg),
                  Expanded(child: selector),
                ],
              )
            else ...[
              current,
              const SizedBox(height: Space.lg),
              selector,
              const SizedBox(height: Space.lg),
              buildInfo,
            ],
          ],
        ),
      ),
    );
  }
}

class _EnvOption extends StatelessWidget {
  const _EnvOption({required this.env, required this.selected, required this.enabled, required this.onTap});

  final EnvironmentConfig env;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final color = environmentColor(env);
    final configured = env.isConfigured;
    return Opacity(
      opacity: configured ? 1 : 0.55,
      child: AppCard(
        key: Key('env-${env.environmentId}'),
        onTap: enabled && configured && !selected ? onTap : null,
        border: true,
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm + 4),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.peach : p.textMuted,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(env.environmentName, style: t.titleSmall)),
                      if (env.isProduction) ...[
                        const SizedBox(width: Space.xs),
                        const AppPill(label: 'Live data', color: AppColors.error, dense: true),
                      ],
                    ],
                  ),
                  Text(
                    configured ? env.baseUrl! : 'Not configured',
                    style: t.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }
}
