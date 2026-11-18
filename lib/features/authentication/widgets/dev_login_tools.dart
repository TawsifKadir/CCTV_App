import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../environments/presentation/providers/environment_providers.dart';
import '../../environments/presentation/widgets/environment_widgets.dart';

/// DEVELOPMENT / QA ONLY. Everything in this file is referenced only behind
/// `!kProductionBuild`, so the compiler removes it (including these strings)
/// from production builds.
class DemoAccount {
  DemoAccount._();
  static const username = 'demo';
  static const password = 'Demo@123';

  static bool matches(String u, String p) => u.trim() == username && p == password;
}

/// "Continue with Demo Account": a local session that never contacts the
/// backend. Visually secondary to the real sign-in.
class DemoLoginCard extends StatelessWidget {
  const DemoLoginCard({super.key, required this.onContinue, this.busy = false});

  final void Function(String username, String password) onContinue;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('demo-login'),
      padding: const EdgeInsets.all(Space.md - 2),
      decoration: BoxDecoration(color: context.palette.accentTint.withValues(alpha: 0.6), borderRadius: Radii.mdAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Demo account (development only)\n', style: t.labelMedium),
                      TextSpan(
                        text: '${DemoAccount.username} · ${DemoAccount.password} — local data only, no server',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          AppSecondaryButton(
            key: const Key('demo-login-button'),
            label: 'Continue with Demo Account',
            icon: Icons.play_circle_outline_rounded,
            variant: AppSecondaryVariant.outline,
            height: 44,
            onPressed: busy ? null : () => onContinue(DemoAccount.username, DemoAccount.password),
          ),
        ],
      ),
    );
  }
}

/// Shown in the status bar during a demo session.
class DemoModeBadge extends StatelessWidget {
  const DemoModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Demo session: data stays on this device and a simulated server',
      child: Container(
        key: const Key('demo-mode-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(Radii.pill)),
        child: Text(
          'DEMO MODE',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.6),
        ),
      ),
    );
  }
}

/// Which backend this sign-in goes to, with a switcher when several are
/// configured (admin builds only).
class DevEnvironmentPicker extends ConsumerWidget {
  const DevEnvironmentPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final build = ref.watch(buildEnvironmentProvider);
    final active = ref.watch(activeEnvironmentProvider);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        runSpacing: 4,
        children: [
          const EnvironmentBadge(dense: true),
          Text(active.baseUrl ?? '', style: t.bodySmall),
          if (build.runtimeSwitchingAllowed && build.available.length > 1)
            PopupMenuButton<String>(
              key: const Key('login-env-picker'),
              tooltip: 'Change environment',
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              onSelected: (id) => ref.read(activeEnvironmentProvider.notifier).select(id),
              itemBuilder: (_) => [
                for (final e in build.available)
                  PopupMenuItem(value: e.environmentId, child: Text('${e.environmentName} · ${e.baseUrl}')),
              ],
            ),
        ],
      ),
    );
  }
}
