import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/data/models/activity.dart';
import 'package:cctv_app/features/employees/presentation/providers/employee_providers.dart';
import 'package:cctv_app/features/registration/domain/employee_photo.dart';
import 'package:cctv_app/features/registration/domain/employee_registration.dart';
import 'package:cctv_app/features/registration/presentation/providers/registration_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestEnv env;

  setUp(() async {
    env = await TestEnv.create();
    // Keep the auto-dispose controller alive for the whole test.
    env.container.listen(registrationControllerProvider, (_, _) {});
  });
  tearDown(() => env.dispose());

  final registration = EmployeeRegistration(
    name: 'Amina Rahman',
    dateOfBirth: DateTime(1998, 5, 20),
    designation: 'QA Analyst',
    photo: EmployeePhoto.fromBytes(fakeJpeg(), origin: PhotoOrigin.camera),
  );

  test('a successful registration returns the outcome and logs activity', () async {
    final outcome = await env.read(registrationControllerProvider.notifier).submit(registration);
    expect(outcome, isNotNull);
    expect(outcome!.environment.environmentId, 'local');
    expect(outcome.result!.recognitionDelayed, isFalse);
    expect(env.read(registrationControllerProvider).submitting, isFalse);
    expect(env.read(activitiesProvider).first.type, ActivityType.employeeRegistered);
    expect(env.read(activitiesProvider).first.environmentId, 'local');
  });

  test('liveWatchList:false is treated as success with a warning', () async {
    env.backend.handler = (_) => json(201, {
          'id': 9,
          'name': 'Amina Rahman',
          'liveWatchList': false,
          'warning': 'Employee saved. Restart the application to load this identity for recognition.',
        });
    final outcome = await env.read(registrationControllerProvider.notifier).submit(registration);
    expect(outcome, isNotNull, reason: 'watch-list warnings must not fail the registration');
    expect(outcome!.result!.recognitionDelayed, isTrue);
    expect(outcome.result!.warningMessage, contains('Restart the application'));
    expect(env.read(registrationControllerProvider).error, isNull);
    expect(env.read(activitiesProvider).first.type, ActivityType.recognitionPending);
  });

  test('backend rejections are surfaced verbatim and nothing is kept locally', () async {
    env.backend.handler = (_) => json(400, {'error': 'Upload a JPEG or PNG photo up to 10 MB.'});
    final outcome = await env.read(registrationControllerProvider.notifier).submit(registration);
    expect(outcome, isNull);
    expect(env.read(registrationControllerProvider).error, 'Upload a JPEG or PNG photo up to 10 MB.');
    expect(env.read(localEmployeeRepositoryProvider).all(), isEmpty);
  });

  test('duplicate submissions are ignored while one is in flight', () async {
    final c = env.read(registrationControllerProvider.notifier);
    final first = c.submit(registration);
    final second = await c.submit(registration);
    expect(second, isNull);
    expect(await first, isNotNull);
    expect(env.backend.requests.where((r) => r.path.endsWith('/employee/add')), hasLength(1));
  });

  test('a registration refreshes the employee list', () async {
    await env.read(serverPageProvider.future);
    expect(env.backend.listRequests, hasLength(1));
    await env.read(registrationControllerProvider.notifier).submit(registration);
    await env.read(serverPageProvider.future);
    final paths = env.backend.requests.map((r) => r.path).toList();
    final post = paths.indexWhere((p) => p.endsWith('/employee/add'));
    expect(paths.lastIndexWhere((p) => p.endsWith('/employee/list')), greaterThan(post),
        reason: 'the list is fetched again from the server after registering');
  });
}
