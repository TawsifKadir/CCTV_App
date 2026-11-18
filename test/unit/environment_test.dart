import 'package:cctv_app/core/config/app_environment.dart';
import 'package:cctv_app/core/config/environment_config.dart';
import 'package:cctv_app/core/config/environment_registry.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/data/models/activity.dart';
import 'package:cctv_app/features/connectivity/connectivity_service.dart';
import 'package:cctv_app/features/employees/data/models/employee.dart';
import 'package:cctv_app/features/employees/presentation/providers/employee_providers.dart';
import 'package:cctv_app/features/environments/presentation/providers/environment_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

const _web = PlatformInfo(isWeb: true, platform: TargetPlatform.android);
const _android = PlatformInfo(isWeb: false, platform: TargetPlatform.android);
const _ios = PlatformInfo(isWeb: false, platform: TargetPlatform.iOS);

BuildEnvironment _resolve({
  String appEnv = '',
  String flavor = '',
  String url = '',
  String host = '',
  PlatformInfo platform = _web,
  bool switching = true,
}) => resolveBuildEnvironment(
  appEnv: appEnv,
  flavor: flavor,
  apiBaseUrlOverride: url,
  localHostOverride: host,
  allowSwitching: switching,
  platform: platform,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local environment', () {
    test('defaults to local on http://localhost:8080 for web and iOS simulator', () {
      final b = _resolve();
      expect(b.config.environmentId, 'local');
      expect(b.config.baseUrl, 'http://localhost:8080');
      expect(b.config.apiBaseUrl, 'http://localhost:8080/api');
      expect(b.source, EnvironmentSource.defaultLocal);
      expect(_resolve(appEnv: 'local', platform: _ios).config.baseUrl, 'http://localhost:8080');
    });

    test('maps localhost to 10.0.2.2 on the Android emulator', () {
      expect(_resolve(appEnv: 'local', platform: _android).config.baseUrl, 'http://10.0.2.2:8080');
    });

    test('LOCAL_API_HOST points physical devices at the developer machine', () {
      expect(
        _resolve(appEnv: 'local', platform: _android, host: '192.168.1.20').config.baseUrl,
        'http://192.168.1.20:8080',
      );
    });
  });

  group('Build environment resolution', () {
    test('production points at the SNOWTEX server and refuses plain HTTP unless acknowledged', () {
      expect(
        () => _resolve(appEnv: 'production'),
        throwsA(isA<EnvironmentConfigurationException>().having((e) => e.message, 'm', contains('HTTPS'))),
      );
      final b = resolveBuildEnvironment(
        appEnv: 'production',
        flavor: '',
        apiBaseUrlOverride: '',
        localHostOverride: '',
        allowInsecureProduction: true,
        platform: _web,
      );
      expect(b.config.baseUrl, 'http://27.147.174.107:8085');
      expect(b.config.apiBaseUrl, 'http://27.147.174.107:8085/api');
      expect(b.config.websiteUrl, 'http://27.147.174.107:8085/');
      expect(b.config.isSecure, isFalse);
      expect(b.runtimeSwitchingAllowed, isFalse);
    });

    test('APP_ENV wins over the flavor', () {
      final b = _resolve(appEnv: 'local', flavor: 'qa');
      expect(b.config.environmentId, 'local');
      expect(b.source, EnvironmentSource.dartDefine);
    });

    test('the flavor is used when APP_ENV is absent', () {
      expect(() => _resolve(flavor: 'qa'), throwsA(isA<EnvironmentConfigurationException>()));
      final b = _resolve(flavor: 'local');
      expect(b.source, EnvironmentSource.flavor);
    });

    test('unconfigured environments fail clearly instead of falling back to localhost', () {
      for (final id in ['development', 'qa']) {
        expect(
          () => _resolve(appEnv: id),
          throwsA(
            isA<EnvironmentConfigurationException>()
                .having((e) => e.environmentId, 'id', id)
                .having((e) => e.message, 'message', contains('No backend URL is configured')),
          ),
        );
      }
    });

    test('unknown environment names are rejected', () {
      expect(
        () => _resolve(appEnv: 'staging'),
        throwsA(
          isA<EnvironmentConfigurationException>().having((e) => e.message, 'm', contains('Unknown environment')),
        ),
      );
    });

    test('API_BASE_URL configures an environment for one build', () {
      final b = _resolve(appEnv: 'qa', url: 'https://qa-api.example.com');
      expect(b.config.environmentId, 'qa');
      expect(b.config.baseUrl, 'https://qa-api.example.com');
    });

    test('invalid URLs are rejected', () {
      expect(() => _resolve(appEnv: 'qa', url: 'not a url'), throwsA(isA<EnvironmentConfigurationException>()));
      expect(() => _resolve(appEnv: 'qa', url: 'ftp://host'), throwsA(isA<EnvironmentConfigurationException>()));
      expect(() => _resolve(appEnv: 'qa', url: 'https://h?x=1'), throwsA(isA<EnvironmentConfigurationException>()));
    });

    test('production requires HTTPS and is locked to itself', () {
      expect(
        () => _resolve(appEnv: 'production', url: 'http://prod.example.com'),
        throwsA(isA<EnvironmentConfigurationException>().having((e) => e.message, 'm', contains('HTTPS'))),
      );
      final prod = _resolve(appEnv: 'production', url: 'https://api.example.com', switching: true);
      expect(prod.config.isProduction, isTrue);
      expect(prod.runtimeSwitchingAllowed, isFalse);
      expect(prod.available.map((e) => e.environmentId), ['production']);
    });

    test('non-production builds can switch only between configured environments', () {
      final b = _resolve(appEnv: 'local');
      expect(b.runtimeSwitchingAllowed, isTrue);
      expect(b.available.map((e) => e.environmentId), [
        'local',
      ], reason: 'dev/QA unconfigured; production needs the HTTP acknowledgement');
      expect(b.unconfigured(platform: _web).map((e) => e.environmentId), ['development', 'qa', 'production']);
      expect(_resolve(appEnv: 'local', switching: false).available, hasLength(1));
    });

    test('every registered environment has a unique id', () {
      final ids = EnvironmentRegistry.ids;
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, containsAll(['local', 'development', 'qa', 'production']));
    });
  });

  group('Runtime switching', () {
    // A build where QA (via override) is the build env, so both QA and the
    // always-configured Local environment are selectable.
    BuildEnvironment twoEnvs() => _resolve(appEnv: 'qa', url: 'https://qa.example.com');

    test('switching updates the API base URL, resets the query and refetches from the new server', () async {
      final env = await TestEnv.create(environment: twoEnvs());
      addTearDown(env.dispose);
      expect(env.read(apiClientProvider).dio.options.baseUrl, 'https://qa.example.com/api');

      env.read(employeeQueryProvider.notifier)
        ..setSearch('Engineer')
        ..setSource(EnrollmentSource.capture)
        ..goToPage(2);
      await env.read(serverPageProvider.future);
      expect(env.backend.last.uri.host, 'qa.example.com');
      final qaRepo = env.read(employeeRepositoryProvider);

      await env.read(activeEnvironmentProvider.notifier).select('local');

      expect(env.read(apiClientProvider).dio.options.baseUrl, 'http://localhost:8080/api');
      expect(env.read(employeeQueryProvider).query, '', reason: 'search cleared');
      expect(env.read(employeeQueryProvider).page, 0, reason: 'pagination reset');
      expect(env.read(employeeQueryProvider).source, isNull);
      expect(identical(env.read(employeeRepositoryProvider), qaRepo), isFalse, reason: 'fresh cache per environment');
      expect(
        env.read(employeeRepositoryProvider).resolvePhotoUrl('/api/employee/1/photo'),
        'http://localhost:8080/api/employee/1/photo',
      );

      await env.read(serverPageProvider.future);
      expect(env.backend.last.uri.host, 'localhost');
      expect(env.read(settingsProvider).selectedEnvironmentId, 'local');
      expect(env.read(activitiesProvider).first.type, ActivityType.environmentChanged);
    });

    test('the selected environment persists across restarts', () async {
      final first = await TestEnv.create(environment: twoEnvs());
      await first.read(activeEnvironmentProvider.notifier).select('local');
      await first.close();
      final second = await TestEnv.create(environment: twoEnvs(), reuse: first.dir);
      addTearDown(second.dispose);
      expect(second.read(activeEnvironmentProvider).environmentId, 'local');
    });

    test('a persisted choice is ignored when the build does not allow it', () async {
      final first = await TestEnv.create(environment: twoEnvs());
      await first.read(activeEnvironmentProvider.notifier).select('local');
      await first.close();
      final locked = await TestEnv.create(
        environment: _resolve(appEnv: 'production', url: 'https://api.example.com'),
        reuse: first.dir,
      );
      addTearDown(locked.dispose);
      expect(locked.read(activeEnvironmentProvider).environmentId, 'production');
      await expectLater(locked.read(activeEnvironmentProvider.notifier).select('local'), throwsStateError);
    });

    test('unconfigured environments cannot be selected', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      await expectLater(env.read(activeEnvironmentProvider.notifier).select('qa'), throwsStateError);
      expect(env.read(activeEnvironmentProvider).environmentId, 'local');
    });

    test('connection status tracks successful and failed calls per environment', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      expect(env.read(connectionStatusProvider).status, NetworkStatus.checking);
      await env.read(connectionStatusProvider.notifier).check();
      expect(env.read(connectionStatusProvider).status, NetworkStatus.online);
      expect(env.read(connectionStatusProvider).lastSuccessAt, isNotNull);

      env.backend.handler = (_) => throw const SocketLikeError('Connection refused');
      await env.read(connectionStatusProvider.notifier).check();
      expect(env.read(connectionStatusProvider).status, NetworkStatus.serverUnavailable);
      expect(env.read(connectionStatusProvider).lastSuccessAt, isNotNull, reason: 'last success is kept');
    });
  });

  test('EnvironmentConfig reports configuration problems', () {
    const missing = EnvironmentConfig(environmentId: 'qa', environmentName: 'QA', baseUrl: null);
    expect(missing.isConfigured, isFalse);
    const ok = EnvironmentConfig(environmentId: 'qa', environmentName: 'QA', baseUrl: 'https://qa.example.com/');
    expect(ok.isConfigured, isTrue);
    expect(ok.apiBaseUrl, 'https://qa.example.com/api');
  });
}

/// Thrown by the fake adapter to simulate a transport failure.
class SocketLikeError implements Exception {
  const SocketLikeError(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
