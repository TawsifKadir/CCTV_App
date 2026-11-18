import 'dart:async';
import 'dart:io';

import 'package:cctv_app/app.dart';
import 'package:cctv_app/core/routing/app_router.dart';
import 'package:cctv_app/core/routing/app_shell.dart';
import 'package:cctv_app/core/routing/routes.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/data/local/local_database.dart';
import 'package:cctv_app/features/authentication/providers/auth_controller.dart';
import 'package:cctv_app/features/employees/data/models/employee.dart';
import 'package:cctv_app/features/employees/data/models/registration_result.dart';
import 'package:cctv_app/features/employees/presentation/providers/employee_providers.dart';
import 'package:cctv_app/core/config/app_environment.dart';
import 'package:cctv_app/core/services/app_notifier.dart';
import 'package:cctv_app/features/employees/data/models/employee_record.dart';
import 'package:cctv_app/features/registration/domain/employee_photo.dart';
import 'package:cctv_app/features/registration/presentation/providers/registration_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

/// Renders the real app (real Hive storage, real Dio client against a fake
/// HTTP adapter) at several screen sizes and exercises the main flows.
/// Layout overflows and build exceptions fail the tests.
void main() {
  late Directory dir;
  late LocalDatabase db;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('enrolly_widget_');
    db = await LocalDatabase.open(path: dir.path);
    final c = ProviderContainer(overrides: [localDatabaseProvider.overrideWithValue(db)]);
    // Reduce motion so decorative repeating animations stop and
    // pumpAndSettle completes.
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(reduceMotion: true));
    c.dispose();
  });

  tearDownAll(() async {
    // Writes issued inside testWidgets' fake-async zone can leave Hive's
    // write queue pending forever, so don't wait indefinitely on close.
    await Future.any([db.close(), Future<void>.delayed(const Duration(seconds: 2))]);
    await dir.delete(recursive: true).catchError((_) => dir);
  });

  const sizes = {
    'phone': Size(390, 844),
    'small phone': Size(360, 700),
    'tablet': Size(820, 1180),
    'desktop': Size(1440, 900),
  };

  Future<(ProviderContainer, FakeBackend)> pumpApp(
    WidgetTester tester,
    Size size, {
    bool signedIn = true,
    FakeBackend? backend,
    FakeDeviceNetwork? network,
    BuildEnvironment? environment,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = backend ?? FakeBackend();
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        initialSessionProvider.overrideWithValue(signedIn ? testSession() : null),
        ...testOverrides(
          backend: fake,
          network: network ?? FakeDeviceNetwork(),
          notifier: AppNotifier(key: GlobalKey<ScaffoldMessengerState>()),
          environment: environment,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EnrollyApp()));
    await tester.pumpAndSettle();
    return (container, fake);
  }

  final sampleEmployee = EmployeeRecord(server: Employee.fromJson(sampleEmployeeJson(id: 1, name: 'Employee 1')));
  RegistrationOutcome outcome({bool delayed = false}) => RegistrationOutcome(
    result: RegistrationResult.fromJson(201, {
      ...sampleEmployeeJson(id: 42, name: 'Amina Rahman'),
      'liveWatchList': !delayed,
      if (delayed) 'warning': 'Employee saved. Recognition will be available when the engine starts.',
    }),
    environment: testBuildEnvironment().config,
    submittedName: 'Amina Rahman',
    designation: 'Software Engineer',
    photo: EmployeePhoto.fromBytes(fakePng(64), origin: PhotoOrigin.upload),
  );

  /// The pagination bar sits below a lazily built list: scroll to it, then
  /// clear it from the floating mobile nav bar.
  Future<void> revealPagination(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('page-next')),
      400,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(find.byKey(const Key('page-next')));
    await tester.pumpAndSettle();
  }

  for (final entry in sizes.entries) {
    testWidgets('all main pages render on ${entry.key}', (tester) async {
      final (container, _) = await pumpApp(tester, entry.value);
      final router = container.read(routerProvider);
      final pages = <(String, Object?)>[
        (Routes.home, null),
        (Routes.employees, null),
        (Routes.employee(sampleEmployee.key), sampleEmployee),
        (Routes.enroll, null),
        (Routes.enrollSuccess, outcome(delayed: true)),
        (Routes.activity, null),
        (Routes.sync, null),
        (Routes.settings, null),
        (Routes.environment, null),
        (Routes.diagnostics, null),
      ];
      for (final (page, extra) in pages) {
        router.go(page, extra: extra);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'exception on $page at ${entry.key}');
      }

      router.go(Routes.home);
      await tester.pumpAndSettle();
      final wide = entry.value.width >= 600;
      expect(find.byType(AppSidebar), wide ? findsOneWidget : findsNothing);
      expect(find.byType(AppBottomNavigation), wide ? findsNothing : findsOneWidget);
    });
  }

  testWidgets('desktop sidebar has the required destinations', (tester) async {
    await pumpApp(tester, const Size(1440, 900));
    for (final label in [
      'Dashboard',
      'Employees',
      'Register Employee',
      'Synchronization',
      'Settings',
      'Environment',
      'Diagnostics',
      'Logout',
    ]) {
      expect(
        find.descendant(of: find.byType(AppSidebar), matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets('mobile bottom bar has Dashboard, Employees, Register, Sync, Settings', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    final nav = find.byType(AppBottomNavigation);
    for (final label in ['Home', 'Employees', 'Sync', 'Settings']) {
      expect(
        find.descendant(of: nav, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.byKey(const Key('nav-register')), findsOneWidget);
  });

  testWidgets('dashboard shows real totals from the list endpoint', (tester) async {
    final (_, backend) = await pumpApp(tester, const Size(1440, 900));
    expect(find.text('On the server'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('stat-total')), matching: find.text('30')), findsOneWidget);
    expect(backend.listRequests, isNotEmpty);
  });

  testWidgets('dashboard shows unavailable figures as "—", not 0, when the backend is down', (tester) async {
    final backend = FakeBackend((_) => throw const SocketException('Connection refused'));
    await pumpApp(tester, const Size(1440, 900), backend: backend);
    expect(find.descendant(of: find.byKey(const Key('stat-total')), matching: find.text('—')), findsOneWidget);
    expect(find.text('Unavailable offline'), findsOneWidget);
    expect(
      find.text('Unable to reach the server. You can continue working with locally stored records.'),
      findsOneWidget,
      reason: 'Wi-Fi is up but the server is not',
    );
  });

  group('Employee list', () {
    testWidgets('loads the first page from the backend', (tester) async {
      final (container, backend) = await pumpApp(tester, const Size(1440, 900));
      container.read(routerProvider).go(Routes.employees);
      await tester.pumpAndSettle();
      expect(find.text('Employee 1'), findsOneWidget);
      expect(find.text('Employee 24'), findsOneWidget);
      expect(find.text('Employee 25'), findsNothing, reason: 'server-side pagination');
      await revealPagination(tester);
      expect(find.byKey(const Key('page-label')), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(backend.listRequests.last.uri.queryParameters, {'page': '0', 'size': '24'});
    });

    testWidgets('search is debounced and resets to the first page', (tester) async {
      final (container, backend) = await pumpApp(tester, const Size(1440, 900));
      container.read(routerProvider).go(Routes.employees);
      await tester.pumpAndSettle();
      await revealPagination(tester);
      await tester.tap(find.byKey(const Key('page-next')));
      await tester.pumpAndSettle();
      expect(backend.listRequests.last.uri.queryParameters['page'], '1');

      final before = backend.listRequests.length;
      await tester.enterText(find.byKey(const Key('employee-search')), 'Eng');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byKey(const Key('employee-search')), 'Engineer');
      await tester.pump(const Duration(milliseconds: 200));
      expect(backend.listRequests.length, before, reason: 'no request while typing');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(backend.listRequests.length, before + 1, reason: 'one request after the pause');
      expect(backend.listRequests.last.uri.queryParameters, {'page': '0', 'size': '24', 'query': 'Engineer'});
    });

    testWidgets('source filter chips map to the backend values', (tester) async {
      final (container, backend) = await pumpApp(tester, const Size(1440, 900));
      container.read(routerProvider).go(Routes.employees);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-capture')));
      await tester.pumpAndSettle();
      expect(backend.listRequests.last.uri.queryParameters['source'], 'capture');
      await tester.tap(find.byKey(const Key('source-photo')));
      await tester.pumpAndSettle();
      expect(backend.listRequests.last.uri.queryParameters['source'], 'photo');
      await tester.tap(find.byKey(const Key('source-all')));
      await tester.pumpAndSettle();
      // "All" omits the parameter (its page is served from the cache here).
      expect(container.read(employeeQueryProvider).source, isNull);
      expect(container.read(employeeQueryProvider).toQueryParameters().containsKey('source'), isFalse);
    });

    testWidgets('pagination moves between server pages', (tester) async {
      final (container, backend) = await pumpApp(tester, const Size(390, 844));
      container.read(routerProvider).go(Routes.employees);
      await tester.pumpAndSettle();
      await revealPagination(tester);
      await tester.tap(find.byKey(const Key('page-next')));
      await tester.pumpAndSettle();
      expect(backend.listRequests.last.uri.queryParameters['page'], '1');
      expect(find.text('Employee 25'), findsOneWidget, reason: 'list scrolls back to the top on a new page');
      await revealPagination(tester);
      expect(find.text('Page 2 of 2'), findsOneWidget);
    });

    testWidgets('shows the loading indicator while a page request is pending', (tester) async {
      Completer<void>? gate;
      final backend = FakeBackend((o) async {
        final g = gate;
        if (g != null) await g.future;
        return FakeBackend.defaultHandler(o);
      });
      final (container, _) = await pumpApp(tester, const Size(1440, 900), backend: backend);
      gate = Completer<void>();
      container.read(routerProvider).go(Routes.employees);
      await tester.pump(); // GoRouter resolves the redirect asynchronously.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Loading employees…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Employee 1'), findsOneWidget);
    });

    testWidgets('shows the backend error with a retry action', (tester) async {
      var fail = true;
      final backend = FakeBackend((o) {
        if (fail && o.path.endsWith('/employee/list') && o.uri.queryParameters['size'] == '24') {
          return json(500, {'error': 'Database unavailable'});
        }
        return FakeBackend.defaultHandler(o);
      });
      final (container, _) = await pumpApp(tester, const Size(1440, 900), backend: backend);
      container.read(routerProvider).go(Routes.employees);
      await tester.pumpAndSettle();
      // Depending on whether server records were cached earlier, the screen
      // shows the error state or the cached copy — always with the server's
      // own message, never silently.
      final errorState = find.text('Could not load employees').evaluate().isNotEmpty;
      expect(errorState || find.byKey(const Key('stale-banner')).evaluate().isNotEmpty, isTrue);
      expect(find.textContaining('Database unavailable'), findsOneWidget);
      fail = false;
      await tester.tap(find.text(errorState ? 'Try again' : 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Employee 1'), findsOneWidget);
    });

    testWidgets('opens the employee profile with the API fields only', (tester) async {
      final (container, _) = await pumpApp(tester, const Size(1440, 900));
      container.read(routerProvider).go(Routes.employees);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Employee 3'));
      await tester.pumpAndSettle();
      expect(find.text('Employee profile'), findsOneWidget);
      expect(find.text('template-3'), findsOneWidget);
      expect(find.text('2,048 bytes'), findsOneWidget);
      expect(find.textContaining('Edit'), findsNothing, reason: 'no update API exists');
      expect(find.textContaining('Delete'), findsNothing, reason: 'no delete API exists');
    });
  });

  group('Registration', () {
    testWidgets('validates every required field without calling the backend', (tester) async {
      final (container, backend) = await pumpApp(tester, const Size(1440, 900));
      container.read(routerProvider).go(Routes.enroll);
      await tester.pumpAndSettle();
      final before = backend.requests.length;
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Date of birth is required'), findsOneWidget);
      expect(find.text('Designation is required'), findsOneWidget);
      expect(find.byKey(const Key('photo-error')), findsOneWidget);
      expect(backend.requests.where((r) => r.path.endsWith('/employee/add')), isEmpty);
      expect(backend.requests.length, before);
    });

    testWidgets('shows the target environment', (tester) async {
      final (container, _) = await pumpApp(tester, const Size(390, 844));
      container.read(routerProvider).go(Routes.enroll);
      await tester.pumpAndSettle();
      expect(find.text('Saving to Local'), findsOneWidget);
      expect(find.byKey(const Key('photo-camera')), findsOneWidget);
      expect(find.byKey(const Key('photo-upload')), findsOneWidget);
    });

    testWidgets('success screen shows a watch-list warning as a warning, not a failure', (tester) async {
      final (container, _) = await pumpApp(tester, const Size(390, 844));
      container.read(routerProvider).go(Routes.enrollSuccess, extra: outcome(delayed: true));
      await tester.pumpAndSettle();
      expect(find.text('Employee registered'), findsOneWidget);
      expect(find.byKey(const Key('watchlist-warning')), findsOneWidget);
      expect(find.text('Employee saved. Recognition will be available when the engine starts.'), findsOneWidget);
      expect(find.text('#1042'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('success-view-employees')));
      await tester.tap(find.byKey(const Key('success-view-employees')));
      await tester.pumpAndSettle();
      expect(find.text('Employees'), findsWidgets);
    });

    testWidgets('success without warnings shows the active watch list', (tester) async {
      final (container, _) = await pumpApp(tester, const Size(1440, 900));
      container.read(routerProvider).go(Routes.enrollSuccess, extra: outcome());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('watchlist-warning')), findsNothing);
      expect(find.text('Active'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('success-register-another')));
      await tester.tap(find.byKey(const Key('success-register-another')));
      await tester.pumpAndSettle();
      expect(find.text('Register employee'), findsWidgets);
    });

    testWidgets('opening the success page without data starts a new registration', (tester) async {
      final (container, _) = await pumpApp(tester, const Size(1440, 900));
      container.read(routerProvider).go(Routes.enrollSuccess);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('register-submit')), findsOneWidget);
    });
  });

  testWidgets('unauthenticated users are redirected to login, which validates input', (tester) async {
    final (container, _) = await pumpApp(tester, const Size(390, 844), signedIn: false);
    container.read(routerProvider).go(Routes.employees);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('environment screen shows the backend and tests the connection', (tester) async {
    final (container, backend) = await pumpApp(tester, const Size(1440, 900));
    container.read(routerProvider).go(Routes.environment);
    await tester.pumpAndSettle();
    expect(find.text('http://localhost:8080'), findsWidgets);
    expect(find.text('Not configured'), findsNWidgets(3));
    final before = backend.requests.length;
    await tester.tap(find.byKey(const Key('test-connection')));
    await tester.pumpAndSettle();
    expect(backend.requests.length, before + 1);
    expect(find.text('Connected'), findsWidgets);
  });
}
