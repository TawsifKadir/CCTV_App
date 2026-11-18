import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/presentation/screens/activity_screen.dart';
import '../../features/authentication/domain/permissions.dart';
import '../../features/authentication/providers/auth_controller.dart';
import '../../features/authentication/screens/login_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/connectivity/app_features_provider.dart';
import '../../features/diagnostics/diagnostics_screen.dart';
import '../../features/employees/data/models/employee_record.dart';
import '../../features/sync/presentation/sync_screen.dart';
import '../../features/employees/presentation/screens/employee_detail_screen.dart';
import '../../features/employees/presentation/screens/employee_list_screen.dart';
import '../../features/environments/presentation/screens/environment_screen.dart';
import '../../features/registration/presentation/providers/registration_controller.dart';
import '../../features/registration/presentation/screens/register_employee_screen.dart';
import '../../features/registration/presentation/screens/registration_success_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../widgets/app_feedback.dart';
import 'app_shell.dart';
import 'routes.dart';

/// Lightweight page transition: a short fade (plus a small slide for pushed
/// detail pages). Kept at ~220 ms because page content has its own brief
/// entrance animations — longer, stacked transitions felt sluggish.
CustomTransitionPage<void> _page(GoRouterState state, Widget child, {bool fadeOnly = false}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondary, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final fade = FadeTransition(opacity: curved, child: child);
      if (fadeOnly) return fade;
      return SlideTransition(
        position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(curved),
        child: fade,
      );
    },
  );
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  // Feature set is fixed for the lifetime of a build.
  final features = ref.read(appFeaturesProvider);
  final signedIn = ValueNotifier<bool>(ref.read(authControllerProvider) != null);
  ref.listen(authControllerProvider, (_, next) => signedIn.value = next != null);
  ref.onDispose(signedIn.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    refreshListenable: signedIn,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onAuthPage = loc == Routes.login;
      if (!signedIn.value && !onAuthPage) return Routes.login;
      if (signedIn.value && onAuthPage) return Routes.home;
      // Role check at routing level (the backend still enforces access).
      if (Routes.requiresAdmin(loc) && !ref.read(permissionsProvider).isAdmin) return Routes.home;
      if (loc == '/') return Routes.home;
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      body: AppEmptyState(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        message: 'The page you were looking for does not exist.',
        actionLabel: 'Go to dashboard',
        onAction: () => context.go(Routes.home),
      ),
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.home),
      GoRoute(path: Routes.login, pageBuilder: (context, state) => _page(state, const LoginScreen(), fadeOnly: true)),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            pageBuilder: (context, state) => _page(state, const DashboardScreen(), fadeOnly: true),
          ),
          GoRoute(
            path: Routes.employees,
            pageBuilder: (context, state) => _page(state, const EmployeeListScreen(), fadeOnly: true),
            routes: [
              GoRoute(
                path: ':key',
                pageBuilder: (context, state) => _page(
                  state,
                  EmployeeDetailScreen(
                    employeeKey: state.pathParameters['key']!,
                    initial: state.extra is EmployeeRecord ? state.extra as EmployeeRecord : null,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(path: Routes.enroll, pageBuilder: (context, state) => _page(state, const RegisterEmployeeScreen())),
          // The outcome is passed in memory; on a reload there is nothing to
          // show, so start a new registration instead.
          GoRoute(
            path: Routes.enrollSuccess,
            redirect: (context, state) => state.extra is RegistrationOutcome ? null : Routes.enroll,
            pageBuilder: (context, state) =>
                _page(state, RegistrationSuccessScreen(outcome: state.extra! as RegistrationOutcome), fadeOnly: true),
          ),
          GoRoute(path: Routes.sync, pageBuilder: (context, state) => _page(state, const SyncScreen(), fadeOnly: true)),
          GoRoute(
            path: Routes.settings,
            pageBuilder: (context, state) => _page(state, const SettingsScreen(), fadeOnly: true),
          ),
          // Admin-only routes: not registered at all in client (production)
          // builds, so they cannot be reached by URL or deep link.
          if (features.activityLog)
            GoRoute(
              path: Routes.activity,
              pageBuilder: (context, state) => _page(state, const ActivityScreen(), fadeOnly: true),
            ),
          if (features.environmentConfiguration)
            GoRoute(
              path: Routes.environment,
              pageBuilder: (context, state) => _page(state, const EnvironmentScreen(), fadeOnly: true),
            ),
          if (features.networkInspector)
            GoRoute(
              path: Routes.diagnostics,
              pageBuilder: (context, state) => _page(state, const DiagnosticsScreen(), fadeOnly: true),
            ),
        ],
      ),
    ],
  );
});
