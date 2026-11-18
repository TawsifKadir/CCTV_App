import 'dart:io';

import 'package:cctv_app/app.dart';
import 'package:cctv_app/core/routing/app_router.dart';
import 'package:cctv_app/core/routing/routes.dart';
import 'package:cctv_app/core/services/app_notifier.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/data/local/local_database.dart';
import 'package:cctv_app/data/models/operator.dart';
import 'package:cctv_app/features/authentication/data/auth_session.dart';
import 'package:cctv_app/features/authentication/domain/permissions.dart';
import 'package:cctv_app/features/authentication/providers/auth_controller.dart';
import 'package:cctv_app/features/employees/data/models/employee.dart';
import 'package:cctv_app/features/employees/data/models/employee_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

const _editMessage = 'Employee editing is not currently available. This feature will be enabled in a future update.';
const _deleteMessage = 'Employee deletion is not currently available. This feature will be enabled in a future update.';

AuthSession _session(List<String> roles) => AuthSession(
  operator: Operator(username: 'u', displayName: 'Test User', roles: roles),
  environmentId: 'local',
  createdAt: DateTime(2026, 11, 18),
  accessToken: 't',
);

void main() {
  group('Permissions', () {
    test('admin role names map to admin', () {
      for (final r in ['admin', 'ADMIN', 'ROLE_ADMIN', 'Administrator']) {
        final p = Permissions.of(_session([r]));
        expect(p.isAdmin, isTrue, reason: r);
        expect(p.canEditEmployees && p.canDeleteEmployees, isTrue);
        expect(p.roleLabel, 'Administrator');
      }
    });

    test('other roles and no session are not admin but can register and view', () {
      for (final s in [
        _session(['user']),
        _session([]),
        null,
      ]) {
        final p = Permissions.of(s);
        expect(p.isAdmin, isFalse);
        expect(p.canEditEmployees || p.canDeleteEmployees, isFalse);
        expect(p.canRegisterEmployees && p.canViewEmployees, isTrue);
      }
    });

    test('admin-only routes', () {
      expect(Routes.requiresAdmin('/employees/42/edit'), isTrue);
      expect(Routes.requiresAdmin('/employees/42/delete'), isTrue);
      expect(Routes.requiresAdmin('/employees/42'), isFalse);
      expect(Routes.requiresAdmin(Routes.employees), isFalse);
    });
  });

  group('Edit / Delete actions', () {
    late Directory dir;
    late LocalDatabase db;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('snowtex_roles_');
      db = await LocalDatabase.open(path: dir.path);
      final c = ProviderContainer(overrides: [localDatabaseProvider.overrideWithValue(db)]);
      await c.read(settingsProvider.notifier).update((s) => s.copyWith(reduceMotion: true, autoSync: false));
      c.dispose();
    });

    tearDownAll(() async {
      await Future.any([db.close(), Future<void>.delayed(const Duration(seconds: 2))]);
      await dir.delete(recursive: true).catchError((_) => dir);
    });

    final record = EmployeeRecord(server: Employee.fromJson(sampleEmployeeJson(id: 7, name: 'Sample Person')));

    Future<ProviderContainer> pump(WidgetTester tester, List<String> roles, {Size size = const Size(1440, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeBackend((o) {
        if (o.path.endsWith('/auth/session')) return fakeSession(o, role: roles.isEmpty ? 'user' : roles.first);
        return FakeBackend.defaultHandler(o);
      });
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(db),
          initialSessionProvider.overrideWithValue(_session(roles)),
          ...testOverrides(
            backend: backend,
            network: FakeDeviceNetwork(),
            notifier: AppNotifier(key: GlobalKey<ScaffoldMessengerState>()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EnrollyApp()));
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> open(WidgetTester tester, ProviderContainer c, String route, {Object? extra}) async {
      c.read(routerProvider).go(route, extra: extra);
      await tester.pumpAndSettle();
    }

    testWidgets('admin sees Edit and Delete; each shows the not-available message', (tester) async {
      final c = await pump(tester, ['admin']);
      await open(tester, c, Routes.employee(record.key), extra: record);

      await tester.tap(find.byKey(const Key('employee-edit')));
      await tester.pumpAndSettle();
      expect(find.text(_editMessage), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('employee-delete')));
      await tester.pumpAndSettle();
      expect(find.text(_deleteMessage), findsOneWidget);
    });

    testWidgets('admin directory table has row Edit and Delete actions', (tester) async {
      final c = await pump(tester, ['admin']);
      await open(tester, c, Routes.employees);
      expect(
        find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('row-edit-')),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('row-delete-')),
        findsWidgets,
      );
    });

    testWidgets('non-admin sees no Edit or Delete anywhere', (tester) async {
      final c = await pump(tester, ['user']);
      await open(tester, c, Routes.employee(record.key), extra: record);
      expect(find.byKey(const Key('employee-edit')), findsNothing);
      expect(find.byKey(const Key('employee-delete')), findsNothing);
      expect(find.byKey(const Key('employee-actions')), findsNothing);

      await open(tester, c, Routes.employees);
      expect(
        find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('row-edit-')),
        findsNothing,
      );
    });

    testWidgets('non-admin is redirected away from admin-only routes', (tester) async {
      final c = await pump(tester, ['user']);
      await open(tester, c, '/employees/7/edit');
      expect(c.read(routerProvider).routerDelegate.currentConfiguration.uri.path, Routes.home);
    });

    testWidgets('phone layout puts admin actions in a menu', (tester) async {
      final c = await pump(tester, ['admin'], size: const Size(390, 844));
      await open(tester, c, Routes.employee(record.key), extra: record);
      await tester.tap(find.byKey(const Key('employee-actions')));
      await tester.pumpAndSettle();
      expect(find.text('Edit employee'), findsOneWidget);
      expect(find.text('Delete employee'), findsOneWidget);
      await tester.tap(find.text('Delete employee'));
      await tester.pumpAndSettle();
      expect(find.text(_deleteMessage), findsOneWidget);
    });
  });
}
