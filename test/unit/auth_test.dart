import 'dart:io';

import 'package:cctv_app/core/network/api_exceptions.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/features/authentication/data/auth_session.dart';
import 'package:cctv_app/features/authentication/providers/auth_controller.dart';
import 'package:cctv_app/features/connectivity/connectivity_service.dart';
import 'package:cctv_app/features/employees/presentation/providers/employee_providers.dart';
import 'package:cctv_app/features/environments/presentation/providers/environment_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestEnv env;

  setUp(() async {
    env = await TestEnv.create();
    env.container.listen(authControllerProvider, (_, _) {});
  });
  tearDown(() => env.dispose());

  AuthController auth() => env.read(authControllerProvider.notifier);

  Future<String> loginError(String u, String p) async {
    try {
      await auth().login(u, p, remember: true);
      fail('expected an error');
    } catch (e) {
      return friendlyAuthError(e);
    }
  }

  group('POST /api/auth/login', () {
    test('sends exactly {username, password} as JSON to the active environment', () async {
      await auth().login(' admin ', testPassword, remember: true);
      final logins = env.backend.requests.where((r) => r.path.endsWith('/auth/login')).toList();
      expect(logins, hasLength(1), reason: 'CSRF token is fetched first, so no 403 round trip');
      expect(env.backend.requests.first.path, endsWith('/auth/csrf'));
      expect(logins.last.headers['X-XSRF-TOKEN'], 'csrf-abc');
      expect(logins.last.headers['Cookie'], contains('XSRF-TOKEN=csrf-abc'));
      final req = logins.last;
      expect(req.uri.toString(), 'http://localhost:8080/api/auth/login');
      expect(req.method, 'POST');
      expect(req.contentType, startsWith('application/json'));
      expect(req.data, {'username': 'admin', 'password': testPassword});
    });

    test('successful login sets the session and the operator', () async {
      await auth().login(testUsername, testPassword, remember: true);
      final s = env.read(authControllerProvider)!;
      expect(s.operator.username, 'admin');
      expect(s.operator.roles, ['admin']);
      expect(s.expiresAt, isNotNull, reason: 'expiresIn 1800s');
      expect(s.environmentId, 'local');
      expect(s.requestHeaders, {'Authorization': 'Bearer tok-123'});
    });

    test('authenticated employee requests carry the session credentials', () async {
      await auth().login(testUsername, testPassword, remember: true);
      await env.read(serverPageProvider.future);
      final list = env.backend.requests.lastWhere((r) => r.path.endsWith('/employee/list'));
      expect(list.headers['Authorization'], 'Bearer tok-123');
    });

    test('a session cookie (e.g. JSESSIONID) is kept and sent back when no token is returned', () async {
      env.backend.handler = (o) => o.path.endsWith('/auth/login')
          ? ResponseBody.fromString(
              '',
              200,
              headers: {
                'set-cookie': ['JSESSIONID=abc123; Path=/; HttpOnly', 'theme=dark; Path=/'],
              },
            )
          : FakeBackend.defaultHandler(o);
      await auth().login(testUsername, testPassword, remember: true);
      final s = env.read(authControllerProvider)!;
      expect(s.accessToken, isNull);
      expect(s.cookies, {'JSESSIONID': 'abc123'}, reason: 'only session cookies, without attributes');
      expect(s.operator.username, testUsername, reason: 'falls back to the entered username');
      await env.read(serverPageProvider.future);
      expect(env.backend.requests.last.headers['Cookie'], 'JSESSIONID=abc123');
    });
  });

  group('Errors', () {
    test('incorrect credentials', () async {
      expect(await loginError('admin', 'wrong'), 'Incorrect username or password.');
      expect(env.read(authControllerProvider), isNull);
    });

    test('HTTP status codes map to friendly messages', () async {
      for (final (status, body, expected) in [
        (400, {'error': 'Username must not be blank.'}, 'Username must not be blank.'),
        (403, <String, dynamic>{}, 'This account is not allowed to sign in.'),
        (404, {'timestamp': 'x', 'status': 404, 'error': 'Not Found'}, contains('not found on this server')),
        (500, <String, dynamic>{}, 'The authentication service is currently unavailable. Please try again later.'),
      ]) {
        env.backend.handler = (_) => json(status, body);
        expect(await loginError('admin', 'x'), expected, reason: 'HTTP $status');
      }
    });

    test('connection refused / timeout / invalid response', () async {
      env.backend.handler = (_) => throw const SocketException('Connection refused');
      expect(
        await loginError('admin', 'x'),
        'Unable to connect to the server. Check your internet connection and try again.',
      );
      env.backend.handler = (o) => throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout);
      expect(await loginError('admin', 'x'), 'The server took too long to respond. Please try again.');
      env.backend.handler = (_) => text(200, '<html>not json</html>');
      expect(await loginError('admin', 'x'), 'The server sent an unexpected response. Please try again later.');
    });

    test('offline login is refused without a request; never a local session', () async {
      env.network.set(DeviceNetwork.none);
      await env.settle();
      expect(await loginError(testUsername, testPassword), startsWith('Unable to connect to the server'));
      expect(env.backend.requests.where((r) => r.path.endsWith('/auth/login')), isEmpty);
      expect(env.read(authControllerProvider), isNull);
    });

    test('a 2xx with an explicit failure flag is a failed login', () async {
      env.backend.handler = (_) => json(200, {'success': false, 'message': 'Account locked'});
      expect(await loginError('admin', 'x'), 'Incorrect username or password.');
    });
  });

  group('Session', () {
    test('"remember me" persists the session securely; off keeps it in memory only', () async {
      await auth().login(testUsername, testPassword, remember: true);
      expect(env.sessions.value?.accessToken, 'tok-123');
      expect(env.read(authRepositoryProvider).rememberedUsername, 'admin');
      await auth().login(testUsername, testPassword, remember: false);
      expect(env.sessions.value, isNull);
      expect(env.read(authRepositoryProvider).rememberedUsername, isNull);
    });

    test('checkAuthenticationStatus restores valid sessions only', () async {
      final repo = env.read(authRepositoryProvider);
      env.sessions.value = testSession();
      expect((await repo.checkAuthenticationStatus('local'))?.operator.username, 'admin');
      env.sessions.value = testSession();
      expect(await repo.checkAuthenticationStatus('development'), isNull, reason: 'other environment');
      env.sessions.value = AuthSession(
        operator: testSession().operator,
        environmentId: 'local',
        createdAt: DateTime(2020),
        expiresAt: DateTime(2021),
      );
      expect(await repo.checkAuthenticationStatus('local'), isNull, reason: 'expired');
      expect(env.sessions.value, isNull, reason: 'stale sessions are removed');
    });

    test('without /auth/csrf, the 403 CSRF challenge is retried once', () async {
      env.backend.handler = (o) =>
          o.path.endsWith('/auth/csrf') ? json(404, {'error': 'Not Found'}) : FakeBackend.defaultHandler(o);
      await auth().login('admin', testPassword, remember: true);
      final logins = env.backend.requests.where((r) => r.path.endsWith('/auth/login')).toList();
      expect(logins, hasLength(2));
      expect(env.read(authControllerProvider)?.accessToken, 'tok-123');
    });

    test('a restored session is validated with GET /api/auth/session (role and expiry updated)', () async {
      final restarted = await TestEnv.create(initialSession: testSession());
      addTearDown(restarted.dispose);
      restarted.container.listen(authControllerProvider, (_, _) {});
      await restarted.read(authControllerProvider.notifier).checkAuthenticationStatus();
      final s = restarted.read(authControllerProvider);
      expect(restarted.backend.requests.any((r) => r.path.endsWith('/auth/session')), isTrue);
      expect(s?.operator.roles, ['admin']);
      expect(s?.expiresAt?.isAfter(DateTime.now()), isTrue);
    });

    test('a restored session the server rejects (401) signs out', () async {
      final restarted = await TestEnv.create(initialSession: testSession());
      addTearDown(restarted.dispose);
      restarted.container.listen(authControllerProvider, (_, _) {});
      restarted.backend.handler = (o) => json(401, {'status': 401});
      await restarted.read(authControllerProvider.notifier).checkAuthenticationStatus();
      await Future<void>.delayed(Duration.zero);
      expect(restarted.read(authControllerProvider), isNull);
    });

    test('a restored session is kept when the server cannot be reached', () async {
      final restarted = await TestEnv.create(initialSession: testSession());
      addTearDown(restarted.dispose);
      restarted.container.listen(authControllerProvider, (_, _) {});
      restarted.backend.handler = (o) => throw const SocketException('down');
      await restarted.read(authControllerProvider.notifier).checkAuthenticationStatus();
      expect(restarted.read(authControllerProvider), isNotNull);
    });

    test('a restored session survives restart', () async {
      final restarted = await TestEnv.create(initialSession: testSession());
      addTearDown(restarted.dispose);
      expect(restarted.read(authControllerProvider)?.operator.username, 'admin');
    });

    test('logout tells the server (POST /api/auth/logout) and clears credentials', () async {
      await auth().login(testUsername, testPassword, remember: true);
      await auth().logout();
      final out = env.backend.requests.lastWhere((r) => r.path.endsWith('/auth/logout'));
      expect(out.headers['Authorization'], 'Bearer tok-123', reason: 'sent while still authenticated');
      expect(env.read(authControllerProvider), isNull);
      expect(env.sessions.value, isNull);
      await env.read(serverPageProvider.future);
      expect(env.backend.requests.last.headers.containsKey('Authorization'), isFalse);
    });

    test('a 401 on an authenticated request expires the session', () async {
      await auth().login(testUsername, testPassword, remember: true);
      env.backend.handler = (o) => o.path.endsWith('/employee/list') ? json(401, {}) : FakeBackend.defaultHandler(o);
      await env.read(connectionStatusProvider.notifier).check();
      await env.settle();
      expect(env.read(authControllerProvider), isNull);
      expect(auth().takeSignOutReason(), 'Your session has expired. Please sign in again.');
    });

    test('switching environment signs out (sessions belong to one backend)', () async {
      final e2 = await TestEnv.create(
        environment: testBuildEnvironment(appEnv: 'qa', apiBaseUrl: 'https://qa.example.com'),
        initialSession: testSession(environmentId: 'qa'),
      );
      addTearDown(e2.dispose);
      e2.container.listen(authControllerProvider, (_, _) {});
      expect(e2.read(authControllerProvider), isNotNull);
      await e2.read(activeEnvironmentProvider.notifier).select('local');
      await e2.settle();
      expect(e2.read(authControllerProvider), isNull);
    });
  });

  test('AuthResponseParser reads nested user info and expiry, ignores unknown fields', () {
    final s = AuthResponseParser.parse(
      body: {
        'token': 'abc',
        'expiresIn': 3600,
        'user': {
          'id': 7,
          'username': 'jdoe',
          'fullName': 'Jane Doe',
          'authorities': [
            {'authority': 'ROLE_OPERATOR'},
          ],
        },
        'somethingElse': true,
      },
      headers: const {},
      enteredUsername: 'ignored',
      environmentId: 'local',
      now: DateTime(2026, 1, 1),
    );
    expect(s.accessToken, 'abc');
    expect(s.requestHeaders['Authorization'], 'Bearer abc');
    expect(s.operator.id, '7');
    expect(s.operator.fullName, 'Jane Doe');
    expect(s.operator.roles, ['ROLE_OPERATOR']);
    expect(s.expiresAt, DateTime(2026, 1, 1, 1));
  });

  group('Demo login (development builds)', () {
    test('validates locally, makes no HTTP request, works offline', () async {
      env.network.set(DeviceNetwork.none);
      await env.settle();
      final before = env.backend.requests.length;
      auth().loginDemo('demo', 'Demo@123');
      final s = env.read(authControllerProvider)!;
      expect(s.isDemo, isTrue);
      expect(s.requestHeaders, isEmpty);
      expect(env.backend.requests.length, before, reason: 'no API request');
      expect(env.sessions.value, isNull, reason: 'demo sessions are never persisted');
      expect(() => auth().loginDemo('demo', 'wrong'), throwsA(isA<ApiException>()));
    });

    test('demo data is isolated and never reaches the real server', () async {
      auth().loginDemo('demo', 'Demo@123');
      expect(env.read(dataScopeProvider), 'demo');
      await env.read(serverPageProvider.future);
      expect(
        env.backend.requests.where((r) => r.path.contains('/employee/')),
        isEmpty,
        reason: 'demo traffic goes to the in-app demo server',
      );
      await auth().logout();
      expect(env.read(dataScopeProvider), 'local');
      expect(env.backend.requests.where((r) => r.path.endsWith('/auth/logout')), isEmpty);
    });

    test('a demo logout does not touch a remembered real session', () async {
      env.sessions.value = testSession();
      auth().loginDemo('demo', 'Demo@123');
      await auth().logout();
      expect(env.sessions.value, isNotNull);
    });

    test('demo login is refused in production (client mode) builds', () async {
      final prod = await TestEnv.create(
        environment: testBuildEnvironment(appEnv: 'production', apiBaseUrl: 'https://api.example.com'),
      );
      addTearDown(prod.dispose);
      expect(() => prod.read(authControllerProvider.notifier).loginDemo('demo', 'Demo@123'), throwsStateError);
    });
  });

  test('the login response is redacted from admin diagnostics', () async {
    await auth().login(testUsername, testPassword, remember: true);
    final entry = env.read(networkLogProvider).value.firstWhere((e) => e.url.contains('/auth/login'));
    expect(entry.requestSummary, '[credentials redacted]');
    expect(entry.responsePreview, '[authentication response redacted]');
    expect('${entry.requestSummary}${entry.responsePreview}', isNot(contains('tok-123')));
  });

  test('ApiException keeps the server message separately', () {
    const e = ApiException(400, 'x', serverMessage: 'x');
    expect(e.serverMessage, 'x');
  });
}
