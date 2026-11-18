import 'package:cctv_app/core/config/app_features.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/features/connectivity/connectivity_service.dart';
import 'package:cctv_app/features/employees/data/models/employee.dart';
import 'package:cctv_app/features/employees/data/models/employee_record.dart';
import 'package:cctv_app/features/employees/data/models/local_employee.dart';
import 'package:cctv_app/features/employees/presentation/providers/employee_providers.dart';
import 'package:cctv_app/features/registration/domain/employee_photo.dart';
import 'package:cctv_app/features/registration/domain/employee_registration.dart';
import 'package:cctv_app/features/registration/presentation/providers/registration_controller.dart';
import 'package:cctv_app/features/sync/data/sync_engine.dart';
import 'package:cctv_app/features/sync/data/sync_history.dart';
import 'package:cctv_app/features/sync/presentation/sync_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

EmployeeRegistration reg(String name, {String designation = 'Engineer'}) => EmployeeRegistration(
  name: name,
  dateOfBirth: DateTime(1995, 3, 14),
  designation: designation,
  photo: EmployeePhoto.fromBytes(fakeJpeg(4096), origin: PhotoOrigin.camera),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeServer server;
  late TestEnv env;

  setUp(() async {
    server = FakeServer();
    env = await TestEnv.create(backend: server.backend);
    env.container.listen(registrationControllerProvider, (_, _) {});
    env.container.listen(syncCoordinatorProvider, (_, _) {});
    env.container.listen(localEmployeesProvider, (_, _) {});
  });
  tearDown(() => env.dispose());

  Future<RegistrationOutcome?> register(String name) =>
      env.read(registrationControllerProvider.notifier).submit(reg(name));

  List<LocalEmployee> locals() => env.read(localEmployeeRepositoryProvider).all();

  Future<void> goOffline() async {
    env.network.set(DeviceNetwork.none);
    await env.settle();
  }

  Future<void> serverDown() async {
    server.down = true;
    await env.read(connectionStatusProvider.notifier).check();
  }

  Future<void> serverBack() async {
    server.down = false;
    env.network.set(DeviceNetwork.wifi);
    await env.settle();
    await env.read(connectionStatusProvider.notifier).check();
    await env.settle();
  }

  group('Scenario A — online registration', () {
    test('uploads, saves the server id locally and marks SYNCED', () async {
      final out = await register('Amina Rahman');
      expect(out!.savedOnServer, isTrue);
      expect(server.postCount, 1);
      final e = locals().single;
      expect(e.syncStatus, SyncStatus.synced);
      expect(e.serverId, 1);
      expect(e.employeeNo, 1001);
      expect(e.lastSuccessfulSync, isNotNull);
      expect(e.localId, isNot('1'), reason: 'local id is a UUID, never the server id');
      expect(
        await env.read(localEmployeeRepositoryProvider).loadPhoto(e.localPhotoReference),
        isNotNull,
        reason: 'photo kept on the device after sync',
      );
    });

    test('appears once, as an "On server" record linked to its local copy', () async {
      await register('Amina Rahman');
      await register('Ben Okafor');
      final listing = env.read(employeeListingProvider);
      await env.read(serverPageProvider.future);
      final l = env.read(employeeListingProvider);
      expect(l.localRecords, isEmpty, reason: 'synced records are not shown twice');
      final records = l.serverRecords(env.read(linkedLocalByServerIdProvider));
      expect(records.map((r) => r.name), ['Ben Okafor', 'Amina Rahman']);
      expect(records.every((r) => r.status == SyncStatus.synced && r.registeredOnThisDevice), isTrue);
      expect(listing.filter, RecordFilter.all);
    });

    test('a server rejection (400) shows the error and keeps nothing', () async {
      server.rejectNames.add('Blurry Photo');
      final out = await register('Blurry Photo');
      expect(out, isNull);
      expect(env.read(registrationControllerProvider).error, 'No face could be detected in the photo.');
      expect(locals(), isEmpty);
    });
  });

  group('Scenario B — offline registration', () {
    test('device offline: saved locally as PENDING_SYNC with its photo; nothing sent', () async {
      await goOffline();
      expect(env.read(connectionStatusProvider).status, NetworkStatus.offline);
      final out = await register('Chen Wei');
      expect(out!.savedOnDeviceOnly, isTrue);
      expect(server.postCount, 0);
      final e = locals().single;
      expect(e.syncStatus, SyncStatus.pendingSync);
      expect(e.serverId, isNull);
      final photo = await env.read(localEmployeeRepositoryProvider).loadPhoto(e.localPhotoReference);
      expect(photo, hasLength(4096));
    });

    test('server unavailable while Wi-Fi is up: status is "Server unavailable", record saved locally', () async {
      await serverDown();
      expect(env.read(connectionStatusProvider).status, NetworkStatus.serverUnavailable);
      expect(env.read(connectionStatusProvider).device, DeviceNetwork.wifi, reason: 'Wi-Fi alone is not "online"');
      final out = await register('Dana Kim');
      expect(out!.savedOnDeviceOnly, isTrue);
      expect(locals().single.syncStatus, SyncStatus.pendingSync);
    });

    test('server drops while uploading: still a local success, never a failure', () async {
      server.down = true; // status still "checking": the app tries, then falls back
      final out = await register('Eli Novak');
      expect(out, isNotNull);
      expect(out!.savedOnDeviceOnly, isTrue);
      expect(env.read(registrationControllerProvider).error, isNull);
      expect(locals().single.syncStatus, SyncStatus.failed);
      expect(locals().single.needsReconciliation, isFalse, reason: 'refused connection: nothing reached the server');
    });

    test('with automatic sync off, offline registrations are LOCAL_ONLY', () async {
      await env.read(settingsProvider.notifier).update((s) => s.copyWith(autoSync: false));
      await goOffline();
      await register('Farah Ali');
      expect(locals().single.syncStatus, SyncStatus.localOnly);
    });
  });

  group('Scenario C — connection restored', () {
    test('automatic sync uploads pending records and notifies', () async {
      await serverDown();
      await register('Gita Rao');
      await register('Hugo Lee');
      expect(server.postCount, 0);
      await serverBack();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.postCount, 2);
      expect(locals().every((e) => e.syncStatus == SyncStatus.synced), isTrue);
      expect(env.notifier.shown, contains(startsWith('Connection restored.')));
      expect(env.notifier.shown, contains('All pending employees have been synchronized.'));
      expect(env.read(syncHistoryProvider).first.trigger, SyncTrigger.automatic);
    });

    test('with automatic sync off it offers manual sync instead of uploading', () async {
      await env.read(settingsProvider.notifier).update((s) => s.copyWith(autoSync: false));
      await serverDown();
      await register('Ivo Petrov');
      await serverBack();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.postCount, 0);
      expect(env.notifier.shown.last, 'Connection restored. You have 1 employee waiting to synchronize.');
      final (start, run) = await env.read(syncControllerProvider.notifier).sync();
      expect(start, SyncStart.started);
      expect(run!.uploaded, 1);
    });

    test('Wi-Fi-only blocks automatic sync on mobile data', () async {
      await env.read(settingsProvider.notifier).update((s) => s.copyWith(syncOnWifiOnly: true));
      await serverDown();
      await register('Jo Park');
      server.down = false;
      env.network.set(DeviceNetwork.mobile);
      await env.settle();
      await env.read(connectionStatusProvider.notifier).check();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.postCount, 0);
    });
  });

  group('Scenario D — synchronization failure', () {
    test('one failing record stays local as FAILED; others upload; Retry failed works', () async {
      await serverDown();
      await register('Kai Wong');
      await register('Rejected Person');
      await register('Lea Moss');
      server.rejectNames.add('Rejected Person');
      server.down = false;
      await env.read(connectionStatusProvider.notifier).check();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final failed = locals().singleWhere((e) => e.name == 'Rejected Person');
      expect(failed.syncStatus, SyncStatus.failed);
      expect(failed.syncError, 'No face could be detected in the photo.');
      expect(failed.permanentFailure, isTrue);
      expect(await env.read(localEmployeeRepositoryProvider).loadPhoto(failed.localPhotoReference), isNotNull);
      expect(locals().where((e) => e.syncStatus == SyncStatus.synced), hasLength(2));
      expect(env.notifier.shown.last, startsWith('Synchronization completed with 1 failed record'));

      // Automatic sync does not hammer a rejected record...
      expect(env.read(syncEngineProvider).candidates(SyncSelection.automatic), isEmpty);
      // ...but Retry failed does try it.
      server.rejectNames.clear();
      final (_, run) = await env.read(syncControllerProvider.notifier).retryFailed();
      expect(run!.uploaded, 1);
      expect(locals().every((e) => e.syncStatus == SyncStatus.synced), isTrue);
    });

    test('Sync now while offline does not start an upload', () async {
      await goOffline();
      await register('Mia Diaz');
      final (start, run) = await env.read(syncControllerProvider.notifier).sync();
      expect(start, SyncStart.offline);
      expect(run, isNull);
      expect(server.postCount, 0);
    });

    test('a single employee can be synchronized on its own', () async {
      await serverDown();
      await register('Nia Brown');
      await register('Omar Said');
      server.down = false;
      await env.read(settingsProvider.notifier).update((s) => s.copyWith(autoSync: false));
      await env.read(connectionStatusProvider.notifier).check();
      final target = locals().singleWhere((e) => e.name == 'Omar Said');
      final (start, r) = await env.read(syncControllerProvider.notifier).syncOne(target.localId);
      expect(start, SyncStart.started);
      expect(r!.outcome, UploadOutcome.uploaded);
      expect(locals().singleWhere((e) => e.name == 'Nia Brown').syncStatus, isNot(SyncStatus.synced));
    });

    test('a batch stops when the server goes down instead of failing every record', () async {
      await serverDown();
      for (final n in ['P1', 'P2', 'P3']) {
        await register(n);
      }
      await env.read(settingsProvider.notifier).update((s) => s.copyWith(autoSync: false));
      server.down = false;
      await env.read(connectionStatusProvider.notifier).check();
      server.down = true;
      final run = await env.read(syncEngineProvider).run(SyncSelection.manual, trigger: SyncTrigger.manual);
      expect(run.aborted, isTrue);
      expect(run.attempted, 1);
      expect(locals().where((e) => e.syncStatus == SyncStatus.pendingSync), hasLength(2));
    });

    test('transient failures back off before automatic retries', () async {
      final engine = env.read(syncEngineProvider);
      expect(engine.retryDelay(1), const Duration(seconds: 30));
      expect(engine.retryDelay(3), const Duration(minutes: 2));
      expect(engine.retryDelay(20), const Duration(minutes: 30));
      server.down = true;
      await register('Quinn Ash'); // fails with a refused connection
      final e = locals().single;
      expect(e.nextRetryAt, isNotNull);
      expect(engine.candidates(SyncSelection.automatic), isEmpty, reason: 'not due yet');
      expect(engine.candidates(SyncSelection.manual), hasLength(1), reason: 'manual retry always possible');
    });
  });

  group('Duplicate prevention', () {
    test('a timeout after the server saved is marked for review, then linked — not uploaded twice', () async {
      server.timeoutAfterSave = true;
      final out = await register('Rosa Diaz');
      expect(out!.savedOnDeviceOnly, isTrue);
      expect(out.uncertain, isTrue);
      final e = locals().single;
      expect(e.syncStatus, SyncStatus.reconciliationRequired);
      expect(e.syncStatus.code, 'RECONCILIATION_REQUIRED');
      expect(server.employees, hasLength(1), reason: 'the server did save it');

      server.timeoutAfterSave = false;
      final r = await env.read(syncEngineProvider).syncRecord(e.localId);
      expect(r.outcome, UploadOutcome.alreadySynced);
      expect(server.postCount, 1, reason: 'no second registration');
      expect(locals().single.serverId, 1);
      expect(locals().single.syncStatus, SyncStatus.synced);
    });

    test('a dropped connection after save is reconciled the same way', () async {
      server.dropResponseAfterSave = true;
      await register('Sam Hill');
      server.dropResponseAfterSave = false;
      final (_, run) = await env.read(syncControllerProvider.notifier).sync();
      expect(run!.alreadySynced, 1);
      expect(server.postCount, 1);
    });

    test('if review finds nothing on the server, it uploads normally', () async {
      server.timeoutAfterSave = true;
      await register('Tia Moon');
      server.employees.clear(); // the server did not keep it after all
      server.timeoutAfterSave = false;
      final r = await env.read(syncEngineProvider).syncRecord(locals().single.localId);
      expect(r.outcome, UploadOutcome.uploaded);
      expect(server.postCount, 2);
      expect(server.employees, hasLength(1));
    });

    test('a server record already linked to another local record is never reused', () async {
      await register('Uma Twin');
      server.timeoutAfterSave = true;
      await register('Uma Twin'); // same details, genuinely a second registration
      server.timeoutAfterSave = false;
      final second = locals().firstWhere((e) => e.syncStatus == SyncStatus.reconciliationRequired);
      final r = await env.read(syncEngineProvider).syncRecord(second.localId);
      expect(r.outcome, UploadOutcome.alreadySynced);
      expect(locals().map((e) => e.serverId).toSet(), {
        1,
        2,
      }, reason: 'each local record maps to its own server record');
    });

    test('concurrent sync requests share one run and each record is sent once', () async {
      await serverDown();
      for (final n in ['V1', 'V2', 'V3']) {
        await register(n);
      }
      await env.read(settingsProvider.notifier).update((s) => s.copyWith(autoSync: false));
      server.down = false;
      await env.read(connectionStatusProvider.notifier).check();
      final engine = env.read(syncEngineProvider);
      final runs = await Future.wait([
        engine.run(SyncSelection.manual, trigger: SyncTrigger.manual),
        engine.run(SyncSelection.manual, trigger: SyncTrigger.manual),
        engine.syncRecord(locals().first.localId).then((_) => null),
      ]);
      expect(identical(runs[0], runs[1]), isTrue);
      expect(server.postCount, 3);
      expect(server.employees, hasLength(3));
    });

    test('test data is never uploaded', () async {
      final repo = env.read(localEmployeeRepositoryProvider);
      await repo.create(reg('Test Employee 1'), status: SyncStatus.pendingSync, isTestData: true);
      final (start, _) = await env.read(syncControllerProvider.notifier).sync();
      expect(start, SyncStart.nothingToSync);
      expect(server.postCount, 0);
    });
  });

  group('Scenario G — restart with pending records', () {
    test('records, photos and states survive a restart; interrupted uploads go to review', () async {
      await serverDown();
      await register('Wren Hale');
      await register('Xia Lin');
      final repo = env.read(localEmployeeRepositoryProvider);
      // Simulate the app being killed during an upload.
      final victim = locals().first;
      await repo.update(victim.localId, (x) => x.copyWith(syncStatus: SyncStatus.syncing));
      final dir = env.dir;
      await env.close();

      env = await TestEnv.create(backend: server.backend, reuse: dir);
      final restored = env.read(localEmployeeRepositoryProvider).all();
      expect(restored, hasLength(2));
      for (final e in restored) {
        expect(await env.read(localEmployeeRepositoryProvider).loadPhoto(e.localPhotoReference), hasLength(4096));
      }
      env.read(syncEngineProvider); // creating the engine recovers interrupted uploads
      await env.settle();
      final after = env.read(localEmployeeRepositoryProvider).get(victim.localId)!;
      expect(after.syncStatus, SyncStatus.reconciliationRequired);
      expect(after.statusLabel, 'Needs review');

      server.down = false;
      await env.read(connectionStatusProvider.notifier).check();
      final (_, run) = await env.read(syncControllerProvider.notifier).sync();
      expect(run!.uploaded, 2);
      expect(env.read(localEmployeeRepositoryProvider).all().every((e) => e.syncStatus == SyncStatus.synced), isTrue);
    });
  });

  group('Offline-aware listing', () {
    test('offline: server records come from the cache, labelled, and search works', () async {
      await register('Yusuf Amin');
      await register('Zara Quinn');
      await env.read(serverPageProvider.future); // caches server records
      await goOffline();
      await register('Offline Person');
      env.read(employeeQueryProvider.notifier).setSearch('zara');
      final page = await env.read(serverPageProvider.future);
      expect(page!.fromCache, isTrue, reason: 'never presented as live');
      expect(page.lastRefresh, isNotNull);
      expect(page.page.content.map((e) => e.name), ['Zara Quinn']);

      env.read(employeeQueryProvider.notifier).setSearch('offline');
      final l = env.read(employeeListingProvider);
      expect(l.localRecords.map((r) => r.name), ['Offline Person']);
      expect(l.localRecords.single.status, SyncStatus.pendingSync);
    });

    test('status filters and counts', () async {
      await serverDown();
      await register('Pending One');
      await env.read(settingsProvider.notifier).update((s) => s.copyWith(autoSync: false));
      await register('Local One');
      final counts = env.read(localCountsProvider);
      expect(counts.pending, 1);
      expect(counts.localOnly, 1);
      expect(counts.awaiting, 2);
      env.read(recordFilterProvider.notifier).set(RecordFilter.localOnly);
      expect(env.read(employeeListingProvider).localRecords.map((r) => r.name), ['Local One']);
      env.read(recordFilterProvider.notifier).set(RecordFilter.pending);
      expect(env.read(employeeListingProvider).localRecords.map((r) => r.name), ['Pending One']);
      env.read(recordFilterProvider.notifier).set(RecordFilter.onServer);
      expect(env.read(employeeListingProvider).localRecords, isEmpty);
    });

    test('dashboard overview is live online and cached (stale) offline', () async {
      await register('Live One');
      final live = await env.read(serverOverviewProvider.future);
      expect(live.fromCache, isFalse);
      expect(live.total, 1);
      await goOffline();
      final cached = await env.read(serverOverviewProvider.future);
      expect(cached.fromCache, isTrue);
      expect(cached.total, 1);
      expect(cached.lastRefresh, isNotNull);
    });

    test('records are found by key after a restart (profiles survive refresh)', () async {
      await goOffline();
      await register('Key Person');
      final key = 'l:${locals().single.localId}';
      expect(env.read(employeeRecordProvider(key))?.name, 'Key Person');
      expect(env.read(employeeRecordProvider('999')), isNull);
    });

    test('local records match the Photo Upload filter only', () async {
      await goOffline();
      await register('Filter Person');
      expect(env.read(employeeListingProvider).localRecords, hasLength(1));
      env.read(employeeQueryProvider.notifier).setSource(EnrollmentSource.capture);
      expect(env.read(employeeListingProvider).localRecords, isEmpty);
      env.read(employeeQueryProvider.notifier).setSource(EnrollmentSource.photo);
      expect(
        env.read(employeeListingProvider).localRecords,
        hasLength(1),
        reason: '/employee/add registrations are recorded by the backend as photo enrolments',
      );
    });
  });

  group('Connectivity', () {
    test('offline vs server unavailable vs online', () async {
      await env.read(connectionStatusProvider.notifier).check();
      expect(env.read(connectionStatusProvider).status, NetworkStatus.online);
      await serverDown();
      expect(env.read(connectionStatusProvider).status, NetworkStatus.serverUnavailable);
      env.network.set(DeviceNetwork.none);
      await env.settle();
      expect(env.read(connectionStatusProvider).status, NetworkStatus.offline);
      expect(env.read(connectionStatusProvider).lastSuccessAt, isNotNull, reason: 'last success kept');
    });

    test('backoff grows exponentially and is capped', () {
      const c = ConnectivityConfig();
      expect(c.backoff(1), const Duration(seconds: 5));
      expect(c.backoff(2), const Duration(seconds: 10));
      expect(c.backoff(4), const Duration(seconds: 40));
      expect(c.backoff(10), const Duration(minutes: 2));
    });

    test('notifications are shown once per transition', () async {
      await env.read(connectionStatusProvider.notifier).check();
      await serverDown();
      await env.read(connectionStatusProvider.notifier).check();
      await env.read(connectionStatusProvider.notifier).check();
      expect(env.notifier.shown.where((m) => m.startsWith('Unable to connect')), hasLength(1));
    });
  });

  group('Feature flags', () {
    test('production builds are client mode; others admin', () {
      expect(AppFeatures.forBuild(testBuildEnvironment()).adminMode, isTrue);
      final prod = testBuildEnvironment(appEnv: 'production', apiBaseUrl: 'https://api.example.com');
      final f = AppFeatures.forBuild(prod, forceClientMode: false);
      expect(f.clientMode, isTrue);
      expect(f.networkInspector || f.environmentConfiguration || f.testDataTools || f.databaseInspector, isFalse);
      expect(
        AppFeatures.forBuild(testBuildEnvironment(), forceClientMode: true).clientMode,
        isTrue,
        reason: 'CLIENT_MODE previews the client UI on a dev build',
      );
    });
  });

  test('EmployeeRecord keys distinguish local and server records', () {
    final l = LocalEmployee.fromJson({
      'localId': 'abc',
      'name': 'X',
      'dateOfBirth': '1990-01-01',
      'designation': 'Y',
      'syncStatus': 'PENDING_SYNC',
      'backendEnvironmentId': 'local',
    });
    expect(EmployeeRecord(local: l).key, 'l:abc');
    expect(EmployeeRecord(local: l).isOnServer, isFalse);
    expect(SyncStatus.fromCode('LOCAL_ONLY'), SyncStatus.localOnly);
  });
}
