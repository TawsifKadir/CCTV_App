// Renders every major screen at several widths, light and dark, to PNG files
// for a visual layout audit (text wrapping, clipping, proportions).
//
//   flutter test test/visual --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Skipped unless SCREENSHOT_DIR is set. Uses the bundled Inter font and the
// Material icon font so text and icons render as in the app.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cctv_app/app.dart';
import 'package:cctv_app/core/config/app_environment.dart';
import 'package:cctv_app/core/routing/app_router.dart';
import 'package:cctv_app/core/routing/routes.dart';
import 'package:cctv_app/core/services/app_notifier.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/data/local/local_database.dart';
import 'package:cctv_app/data/models/operator.dart';
import 'package:cctv_app/features/authentication/data/auth_session.dart';
import 'package:cctv_app/features/authentication/providers/auth_controller.dart';
import 'package:cctv_app/features/employees/data/models/employee.dart';
import 'package:cctv_app/features/employees/data/models/employee_record.dart';
import 'package:cctv_app/features/employees/data/models/local_employee.dart';
import 'package:cctv_app/features/employees/presentation/providers/employee_providers.dart';
import 'package:cctv_app/features/environments/presentation/providers/environment_providers.dart';
import 'package:cctv_app/features/registration/domain/employee_photo.dart';
import 'package:cctv_app/features/registration/domain/employee_registration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

const _outDir = String.fromEnvironment('SCREENSHOT_DIR');

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest) {
    final loader = FontLoader(family['family'] as String);
    for (final f in family['fonts'] as List) {
      loader.addFont(rootBundle.load(f['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  late Directory dir;
  late LocalDatabase db;
  final skip = _outDir.isEmpty ? 'Set --dart-define=SCREENSHOT_DIR=<dir>' : null;

  setUpAll(() async {
    if (skip != null) return;
    await _loadFonts();
    dir = await Directory.systemTemp.createTemp('snowtex_shots_');
    db = await LocalDatabase.open(path: dir.path);
    final c = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        buildEnvironmentProvider.overrideWithValue(testBuildEnvironment()),
      ],
    );
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(reduceMotion: true, autoSync: false));
    final repo = c.read(localEmployeeRepositoryProvider);
    EmployeeRegistration reg(String n, String d) => EmployeeRegistration(
      name: n,
      dateOfBirth: DateTime(1994, 3, 2),
      designation: d,
      photo: EmployeePhoto.fromBytes(fakePng(64), origin: PhotoOrigin.camera),
    );
    await repo.create(reg('Nusrat Jahan Chowdhury', 'Quality Assurance Supervisor'), status: SyncStatus.pendingSync);
    final r = await repo.create(reg('Tanvir Hasan', 'Machine Operator'), status: SyncStatus.pendingSync);
    await repo.update(r.localId, (x) => x.copyWith(syncStatus: SyncStatus.reconciliationRequired));
    c.dispose();
  });

  tearDownAll(() async {
    if (skip != null) return;
    await Future.any([db.close(), Future<void>.delayed(const Duration(seconds: 2))]);
  });

  final admin = AuthSession(
    operator: const Operator(username: 'kitbd', displayName: 'Mahmudul Karim', roles: ['admin']),
    environmentId: 'local',
    createdAt: DateTime(2026, 11, 18),
    accessToken: 't',
  );

  FakeBackend backend() => FakeBackend((o) {
    if (o.path.endsWith('/employee/list')) {
      final names = [
        'Farzana Akter',
        'Md. Rakibul Islam',
        'Shahriar Ahmed Khan',
        'Sumaiya Rahman',
        'Abdullah Al Mamun',
      ];
      final desig = ['Sewing Operator', 'Senior Merchandiser', 'Production Manager', 'HR Executive', 'Security Guard'];
      return json(200, {
        'content': [
          for (var i = 0; i < 5; i++)
            {
              ...sampleEmployeeJson(id: 101 + i, name: names[i], source: i.isEven ? 'photo' : 'capture'),
              'designation': desig[i],
            },
        ],
        'page': 0,
        'size': 24,
        'totalElements': 5,
        'totalPages': 1,
        'hasPrevious': false,
        'hasNext': false,
      });
    }
    return FakeBackend.defaultHandler(o);
  });

  const sizes = {'s360': Size(360, 740), 'p390': Size(390, 844), 't820': Size(820, 1180), 'd1440': Size(1440, 900)};

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Size size, {
    String? route,
    Object? extra,
    bool signedIn = true,
    Brightness brightness = Brightness.light,
    BuildEnvironment? env,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        initialSessionProvider.overrideWithValue(signedIn ? admin : null),
        ...testOverrides(
          backend: backend(),
          network: FakeDeviceNetwork(),
          notifier: AppNotifier(key: GlobalKey<ScaffoldMessengerState>()),
          environment: env,
        ),
      ],
    );
    addTearDown(container.dispose);
    const key = Key('shot');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: UncontrolledProviderScope(container: container, child: const EnrollyApp()),
      ),
    );
    await tester.pumpAndSettle();
    if (route != null) {
      container.read(routerProvider).go(route, extra: extra);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull, reason: name);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = await boundary.toImage(pixelRatio: size.width > 1000 ? 0.75 : 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  final server = EmployeeRecord(
    server: Employee.fromJson({
      ...sampleEmployeeJson(id: 103, name: 'Shahriar Ahmed Khan'),
      'designation': 'Production Manager',
    }),
  );
  final prod = testBuildEnvironment(appEnv: 'production', allowInsecureProduction: true);

  group('screens', skip: skip, () {
    for (final e in sizes.entries) {
      testWidgets('login ${e.key}', (t) => shoot(t, 'login_dev_${e.key}', e.value, signedIn: false));
      testWidgets('dashboard ${e.key}', (t) => shoot(t, 'dashboard_${e.key}', e.value));
      testWidgets('register ${e.key}', (t) => shoot(t, 'register_${e.key}', e.value, route: Routes.enroll));
      testWidgets('employees ${e.key}', (t) => shoot(t, 'employees_${e.key}', e.value, route: Routes.employees));
      testWidgets(
        'detail ${e.key}',
        (t) => shoot(t, 'detail_${e.key}', e.value, route: Routes.employee(server.key), extra: server),
      );
      testWidgets('sync ${e.key}', (t) => shoot(t, 'sync_${e.key}', e.value, route: Routes.sync));
      testWidgets('settings ${e.key}', (t) => shoot(t, 'settings_${e.key}', e.value, route: Routes.settings));
    }
    testWidgets('login prod', (t) => shoot(t, 'login_prod_p390', sizes['p390']!, signedIn: false, env: prod));
    for (final s in ['p390', 'd1440']) {
      testWidgets('dark dashboard $s', (t) => shoot(t, 'dark_dashboard_$s', sizes[s]!, brightness: Brightness.dark));
      testWidgets(
        'dark employees $s',
        (t) => shoot(t, 'dark_employees_$s', sizes[s]!, route: Routes.employees, brightness: Brightness.dark),
      );
      testWidgets(
        'dark register $s',
        (t) => shoot(t, 'dark_register_$s', sizes[s]!, route: Routes.enroll, brightness: Brightness.dark),
      );
    }
  });
}
