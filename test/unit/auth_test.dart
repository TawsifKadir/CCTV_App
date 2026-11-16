import 'package:cctv_app/core/constants/app_constants.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/core/utils/password_hasher.dart';
import 'package:cctv_app/data/remote/demo_auth_api.dart';
import 'package:cctv_app/data/remote/api_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.dispose());

  const request = RegisterRequest(
    fullName: 'Robin Field',
    email: 'Robin@Example.com',
    phone: '+1 555 222 3333',
    password: 'Secret123',
    organization: 'North Branch',
  );

  group('Operator registration', () {
    test('creates an operator, stores it and starts a session', () async {
      final repo = env.read(authRepositoryProvider);
      final op = await repo.register(request);

      expect(op.fullName, 'Robin Field');
      expect(op.email, 'robin@example.com', reason: 'emails are normalised');
      expect(op.organization, 'North Branch');
      expect(env.read(demoAuthApiProvider).hasOperator('robin@example.com'), isTrue);
      expect((await repo.restoreSession())?.id, op.id);
    });

    test('rejects a duplicate email (case-insensitive)', () async {
      final repo = env.read(authRepositoryProvider);
      await repo.register(request);
      await expectLater(
        repo.register(const RegisterRequest(
          fullName: 'Other Person',
          email: 'ROBIN@example.com',
          phone: '+1 555 222 4444',
          password: 'Secret123',
        )),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('never stores the password in plain text', () async {
      await env.read(authRepositoryProvider).register(request);
      final raw = env.db.box(BoxNames.demoOperators).get('robin@example.com') as String;
      expect(raw.contains('Secret123'), isFalse);
      expect(raw.contains('pbkdf2'), isTrue);
    });

    test('supports multiple operators', () async {
      final repo = env.read(authRepositoryProvider);
      await repo.register(request);
      await repo.register(const RegisterRequest(
        fullName: 'Sam Second',
        email: 'sam@example.com',
        phone: '+1 555 222 5555',
        password: 'Another123',
      ));
      expect((await repo.login('robin@example.com', 'Secret123', remember: true)).fullName, 'Robin Field');
      expect((await repo.login('sam@example.com', 'Another123', remember: true)).fullName, 'Sam Second');
    });
  });

  group('Operator login', () {
    setUp(() async {
      await env.read(demoAuthApiProvider).ensureDemoOperator();
    });

    test('accepts the demo credentials', () async {
      final op = await env.read(authRepositoryProvider)
          .login(AppConstants.demoEmail, AppConstants.demoPassword, remember: true);
      expect(op.email, AppConstants.demoEmail);
    });

    test('rejects a wrong password with a friendly message', () async {
      await expectLater(
        env.read(authRepositoryProvider).login(AppConstants.demoEmail, 'wrong', remember: true),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.message, 'message', 'Incorrect email or password')),
      );
    });

    test('rejects an unknown account', () async {
      await expectLater(
        env.read(authRepositoryProvider).login('nobody@example.com', 'Admin@123', remember: true),
        throwsA(isA<ApiException>()),
      );
    });

    test('"remember me" controls whether the session survives a restart', () async {
      final repo = env.read(authRepositoryProvider);
      await repo.login(AppConstants.demoEmail, AppConstants.demoPassword, remember: false);
      expect(await repo.restoreSession(), isNull);

      await repo.login(AppConstants.demoEmail, AppConstants.demoPassword, remember: true);
      expect(await repo.restoreSession(), isNotNull);

      await repo.logout();
      expect(await repo.restoreSession(), isNull);
    });
  });

  test('the demo operator is created once and existing accounts survive', () async {
    final api = env.read(demoAuthApiProvider);
    await api.ensureDemoOperator();
    await api.ensureDemoOperator();
    expect(api.hasOperator(AppConstants.demoEmail), isTrue);
    expect(DemoAuthApi.demoOperator.email, AppConstants.demoEmail);
  });

  test('PasswordHasher verifies only the original password', () {
    final h = PasswordHasher.hash('Admin@123');
    expect(PasswordHasher.verify('Admin@123', h), isTrue);
    expect(PasswordHasher.verify('admin@123', h), isFalse);
    expect(PasswordHasher.hash('Admin@123'), isNot(h), reason: 'random salt per hash');
  });
}
