import 'dart:io';

import 'package:cctv_app/app.dart';
import 'package:cctv_app/core/config/app_environment.dart';
import 'package:cctv_app/core/routing/app_router.dart';
import 'package:cctv_app/core/routing/app_shell.dart';
import 'package:cctv_app/core/routing/routes.dart';
import 'package:cctv_app/core/services/app_notifier.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/data/local/local_database.dart';
import 'package:cctv_app/features/authentication/providers/auth_controller.dart';
import 'package:cctv_app/features/connectivity/connectivity_service.dart';
import 'package:cctv_app/features/employees/data/models/local_employee.dart';
import 'package:cctv_app/features/employees/presentation/providers/employee_providers.dart';
import 'package:cctv_app/features/environments/presentation/widgets/environment_widgets.dart';
import 'package:cctv_app/features/registration/domain/employee_photo.dart';
import 'package:cctv_app/features/registration/domain/employee_registration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

/// Client (production) vs admin builds, and the offline-first UI.
void main() {
  late Directory dir;
  late LocalDatabase db;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('enrolly_modes_');
    db = await LocalDatabase.open(path: dir.path);
    final c = ProviderContainer(overrides: [localDatabaseProvider.overrideWithValue(db)]);
    // Automatic sync is covered by unit tests; here it would start uploads
    // whose storage writes can't complete inside the fake-async test zone.
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(reduceMotion: true, autoSync: false));
    c.dispose();
  });

  tearDownAll(() async {
    await Future.any([db.close(), Future<void>.delayed(const Duration(seconds: 2))]);
    await dir.delete(recursive: true).catchError((_) => dir);
  });

  final production = testBuildEnvironment(appEnv: 'production', apiBaseUrl: 'https://api.example.com');

  Future<(ProviderContainer, FakeDeviceNetwork)> pump(
    WidgetTester tester, {
    bool signedIn = true,
    Size size = const Size(1440, 900),
    BuildEnvironment? environment,
    FakeBackend? backend,
    DeviceNetwork device = DeviceNetwork.wifi,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final network = FakeDeviceNetwork(device);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        initialSessionProvider.overrideWithValue(
          signedIn ? testSession(environmentId: (environment ?? testBuildEnvironment()).config.environmentId) : null,
        ),
        ...testOverrides(
          backend: backend ?? FakeBackend(),
          network: network,
          notifier: AppNotifier(key: GlobalKey<ScaffoldMessengerState>()),
          environment: environment,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EnrollyApp()));
    await tester.pumpAndSettle();
    return (container, network);
  }

  Future<void> go(WidgetTester tester, ProviderContainer c, String route, {Object? extra}) async {
    c.read(routerProvider).go(route, extra: extra);
    await tester.pumpAndSettle();
  }

  group('Production build — client mode', () {
    testWidgets('navigation has only client destinations', (tester) async {
      await pump(tester, environment: production);
      final sidebar = find.byType(AppSidebar);
      for (final label in ['Dashboard', 'Employees', 'Register Employee', 'Synchronization', 'Settings', 'Logout']) {
        expect(
          find.descendant(of: sidebar, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.descendant(of: sidebar, matching: find.text('Environment')), findsNothing);
      expect(find.descendant(of: sidebar, matching: find.text('Diagnostics')), findsNothing);
      expect(find.byType(EnvironmentBadge), findsNothing, reason: 'no environment indicator for clients');
    });

    testWidgets('developer routes are not registered (not just hidden)', (tester) async {
      final (c, _) = await pump(tester, environment: production);
      for (final route in [Routes.diagnostics, Routes.environment, Routes.activity]) {
        await go(tester, c, route);
        expect(find.text('Page not found'), findsOneWidget, reason: route);
      }
    });

    testWidgets('settings and registration show no backend URLs or developer tools', (tester) async {
      final (c, _) = await pump(tester, environment: production);
      await go(tester, c, Routes.settings);
      expect(find.text('Synchronization'), findsWidgets);
      expect(find.text('Automatic synchronization'), findsOneWidget);
      expect(find.text('Clear local data'), findsOneWidget);
      expect(find.text('BACKEND (DEVELOPER)'), findsNothing);
      expect(find.text('Diagnostics'), findsNothing);
      expect(find.textContaining('api.example.com'), findsNothing);
      await go(tester, c, Routes.enroll);
      expect(find.text('Saving to the server'), findsOneWidget);
      expect(find.textContaining('api.example.com'), findsNothing);
    });

    testWidgets('dashboard has the client figures', (tester) async {
      await pump(tester, environment: production);
      for (final k in [
        'dashboard-welcome',
        'action-register',
        'action-employees',
        'stat-total',
        'stat-pending',
        'stat-synced',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.text('Welcome, Admin User'), findsOneWidget);
      expect(find.text('Recent activity'), findsNothing, reason: 'no technical panels');
      expect(find.byKey(const Key('connection-banner')), findsNothing, reason: 'no permanent online badge');
      expect(find.text('Online'), findsNothing);
    });
  });

  group('Development build — admin mode', () {
    testWidgets('keeps environment indicator, configuration and diagnostics', (tester) async {
      final (c, _) = await pump(tester);
      expect(find.byType(EnvironmentBadge), findsWidgets);
      expect(find.descendant(of: find.byType(AppSidebar), matching: find.text('Diagnostics')), findsOneWidget);
      await go(tester, c, Routes.diagnostics);
      for (final tab in ['Network', 'Sync log', 'Local data', 'Tools']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.textContaining('/api/employee/list'), findsWidgets, reason: 'network inspector recorded requests');
      await go(tester, c, Routes.settings);
      expect(find.text('BACKEND (DEVELOPER)'), findsOneWidget);
      expect(find.text('Connection check interval'), findsOneWidget);
    });
  });

  group('Offline-first UI', () {
    Future<void> seed(WidgetTester tester, ProviderContainer c, String name, SyncStatus status) async {
      await tester.runAsync(() async {
        await c
            .read(localEmployeeRepositoryProvider)
            .create(
              EmployeeRegistration(
                name: name,
                dateOfBirth: DateTime(1990, 1, 1),
                designation: 'Clerk',
                photo: EmployeePhoto.fromBytes(fakePng(64), origin: PhotoOrigin.upload),
              ),
              status: status,
            );
      });
      await tester.pumpAndSettle();
    }

    Future<void> clearLocal(WidgetTester tester, ProviderContainer c) async {
      await tester.runAsync(() => c.read(localEmployeeRepositoryProvider).clear());
      await tester.pumpAndSettle();
    }

    testWidgets('status indicator and dashboard follow connectivity changes', (tester) async {
      final (c, network) = await pump(tester, size: const Size(390, 844));
      expect(find.byKey(const Key('connection-banner')), findsNothing, reason: 'nothing shown while working');
      network.set(DeviceNetwork.none);
      await tester.pumpAndSettle();
      expect(find.text("You're offline. Your registrations are safe."), findsOneWidget);
      network.set(DeviceNetwork.wifi);
      await tester.pump();
      await tester.runAsync(() => c.read(connectionStatusProvider.notifier).check());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connection-banner')), findsNothing);
    });

    testWidgets('local records are listed with status badges and filter counts', (tester) async {
      final (c, _) = await pump(tester);
      await seed(tester, c, 'Pending Paula', SyncStatus.pendingSync);
      await seed(tester, c, 'Local Lars', SyncStatus.localOnly);
      await go(tester, c, Routes.employees);
      expect(find.text('On this device'), findsOneWidget);
      expect(find.text('Pending Paula'), findsOneWidget);
      expect(find.byKey(const Key('sync-badge-PENDING_SYNC')), findsWidgets);
      expect(find.byKey(const Key('sync-badge-LOCAL_ONLY')), findsWidgets);
      expect(find.byKey(const Key('sync-badge-SYNCED')), findsWidgets, reason: 'server records are marked On server');
      expect(find.text('Local only  1'), findsOneWidget);
      expect(find.text('Pending sync  1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('filter-localOnly')));
      await tester.pumpAndSettle();
      expect(find.text('Local Lars'), findsOneWidget);
      expect(find.text('Pending Paula'), findsNothing);
      expect(find.text('Employee 1'), findsNothing, reason: 'server records hidden for device-only filters');
      await clearLocal(tester, c);
    });

    testWidgets('offline: Sync now explains records are safe and offers retry options', (tester) async {
      final (c, _) = await pump(tester, device: DeviceNetwork.none);
      await seed(tester, c, 'Offline Olga', SyncStatus.pendingSync);
      await go(tester, c, Routes.sync);
      expect(find.byKey(const Key('offline-card')), findsOneWidget);
      expect(find.text("You're working offline."), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-sync')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline-sync-dialog')), findsOneWidget);
      expect(find.text('You are currently offline'), findsOneWidget);
      for (final label in ['Retry connection', 'Try again', 'Cancel']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await clearLocal(tester, c);
    });

    testWidgets('offline registration form says it will save on this device', (tester) async {
      final (c, _) = await pump(tester, device: DeviceNetwork.none);
      await go(tester, c, Routes.enroll);
      expect(find.text('Saving on this device'), findsOneWidget);
    });

    testWidgets('local profile explains it has not been uploaded and offers sync', (tester) async {
      final (c, _) = await pump(tester, device: DeviceNetwork.none);
      await seed(tester, c, 'Profile Pia', SyncStatus.pendingSync);
      final id = c.read(localEmployeesProvider).first.localId;
      await go(tester, c, Routes.employee('l:$id'));
      expect(find.byKey(const Key('not-uploaded-banner')), findsOneWidget);
      expect(find.text('On this device only'), findsOneWidget);
      expect(find.text(id), findsOneWidget, reason: 'local record id shown');
      expect(find.byKey(const Key('sync-one')), findsOneWidget);
      await clearLocal(tester, c);
    });
  });

  group('Login', () {
    testWidgets('development builds offer Continue with Demo Account (no API call, DEMO MODE shown)', (tester) async {
      final (c, _) = await pump(tester, signedIn: false, size: const Size(390, 844));
      expect(find.byKey(const Key('demo-login')), findsOneWidget);
      expect(find.textContaining('Demo@123', findRichText: true), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('demo-login-button')));
      await tester.tap(find.byKey(const Key('demo-login-button')));
      await tester.pumpAndSettle();
      expect(c.read(authControllerProvider)?.isDemo, isTrue);
      expect(find.byType(AppBottomNavigation), findsOneWidget, reason: 'navigated to the dashboard');
      expect(find.byKey(const Key('demo-mode-badge')), findsOneWidget);
    });

    testWidgets('real sign-in reaches the dashboard without DEMO MODE', (tester) async {
      final (c, _) = await pump(tester, signedIn: false);
      await tester.enterText(find.byKey(const Key('login-username')), testUsername);
      await tester.enterText(find.byKey(const Key('login-password')), testPassword);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('login-submit')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(c.read(authControllerProvider)?.isDemo, isFalse);
      expect(find.byKey(const Key('demo-mode-badge')), findsNothing);
    });

    testWidgets('production builds show no demo credentials or developer tools', (tester) async {
      await pump(tester, signedIn: false, environment: production);
      expect(find.byKey(const Key('demo-login')), findsNothing);
      expect(find.text('Continue with Demo Account'), findsNothing);
      expect(find.textContaining('Demo@123', findRichText: true), findsNothing);
      expect(find.byType(EnvironmentBadge), findsNothing);
      expect(find.byKey(const Key('login-username')), findsOneWidget);
    });

    testWidgets('wrong credentials show a friendly error', (tester) async {
      await pump(tester, signedIn: false);
      await tester.enterText(find.byKey(const Key('login-username')), 'admin');
      await tester.enterText(find.byKey(const Key('login-password')), 'nope');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect username or password.'), findsOneWidget);
    });

    testWidgets('logout returns to login and protected routes redirect there', (tester) async {
      final (c, _) = await pump(tester);
      await go(tester, c, Routes.settings);
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      await go(tester, c, Routes.employees);
      expect(find.text('Welcome back'), findsOneWidget, reason: 'protected route redirects to login');
    });
  });
}
