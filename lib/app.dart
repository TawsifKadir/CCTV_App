import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_environment.dart';
import 'core/constants/app_constants.dart';
import 'core/routing/app_router.dart';
import 'core/services/app_notifier.dart';
import 'core/services/providers.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/enrolly_logo.dart';

class EnrollyApp extends ConsumerWidget {
  const EnrollyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final reduceMotion = ref.watch(settingsProvider.select((s) => s.reduceMotion));
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // ThemeMode.system (the default) follows the device appearance live.
      themeMode: themeMode,
      routerConfig: router,
      scaffoldMessengerKey: appMessengerKey,
      builder: (context, child) {
        // Honour both the OS accessibility setting and the in-app
        // "Reduce motion" preference everywhere via MediaQuery.
        final osReduce = MediaQuery.disableAnimationsOf(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: osReduce || reduceMotion),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Shown instead of the app when the build's environment is unknown or has
/// no valid backend URL.
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key, required this.error});

  final EnvironmentConfigurationException error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${AppConstants.appName} — configuration error',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Builder(
        builder: (context) {
          final t = Theme.of(context).textTheme;
          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const EnrollyLogoMark(size: 56),
                      const SizedBox(height: Space.lg),
                      Text('Backend not configured', style: t.headlineMedium),
                      const SizedBox(height: Space.xs),
                      Text(
                        'This build targets the "${error.environmentId}" environment, which cannot be used.',
                        style: t.bodyLarge?.copyWith(color: context.palette.textMuted),
                      ),
                      const SizedBox(height: Space.lg),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: Radii.mdAll,
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
                        ),
                        child: SelectableText(error.message, style: t.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
