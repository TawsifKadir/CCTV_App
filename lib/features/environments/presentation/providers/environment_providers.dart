import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/config/environment_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../../core/services/providers.dart';
import '../../../../data/models/activity.dart';
import '../../../../core/config/app_features.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../authentication/providers/auth_controller.dart';
import '../../../demo/demo_backend.dart';
import '../../../connectivity/app_features_provider.dart';
import '../../../connectivity/connectivity_service.dart';
import '../../../diagnostics/data/network_log.dart';

/// The build's environment. Overridden in `main()` (and in tests).
final buildEnvironmentProvider = Provider<BuildEnvironment>(
  (ref) => throw UnimplementedError('buildEnvironmentProvider must be overridden'),
);

/// The backend environment every request currently goes to.
///
/// Production builds are locked to their own environment. Other builds may
/// switch between configured environments in Settings; the choice persists.
class ActiveEnvironmentController extends Notifier<EnvironmentConfig> {
  @override
  EnvironmentConfig build() {
    final build = ref.watch(buildEnvironmentProvider);
    if (!build.runtimeSwitchingAllowed) return build.config;
    final saved = ref.read(settingsProvider).selectedEnvironmentId;
    return (saved == null ? null : build.byId(saved)) ?? build.config;
  }

  BuildEnvironment get _build => ref.read(buildEnvironmentProvider);

  /// Switches the active environment. Everything that depends on it (API
  /// client, repositories, queries, connection status) is rebuilt by
  /// Riverpod, and decoded photos from the previous server are evicted.
  Future<void> select(String environmentId) async {
    final build = _build;
    if (!build.runtimeSwitchingAllowed) {
      throw StateError('This ${build.config.environmentName} build cannot switch environments.');
    }
    final target = build.byId(environmentId);
    if (target == null) throw StateError('Environment "$environmentId" is not configured.');
    if (target == state) return;
    final previous = state;
    state = target;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(selectedEnvironmentId: () => environmentId));
    await ref
        .read(activityRepositoryProvider)
        .log(
          ActivityType.environmentChanged,
          'Switched to ${target.environmentName}',
          subtitle: 'From ${previous.environmentName} · ${target.baseUrl}',
          environmentId: target.environmentId,
        );
  }
}

final activeEnvironmentProvider = NotifierProvider<ActiveEnvironmentController, EnvironmentConfig>(
  ActiveEnvironmentController.new,
);

/// Creates the underlying [Dio]. Overridden in tests to plug in a fake
/// HTTP adapter; the app uses the platform default.
final dioFactoryProvider = Provider<Dio Function()>((ref) => Dio.new);

/// `true` during a demo session (non-production builds only). Set by
/// AuthController; kept separate from the session so the HTTP client does
/// not depend on the auth state (which itself uses the client).
class DemoModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool on) => state = !kProductionBuild && on;
}

final isDemoSessionProvider = NotifierProvider<DemoModeNotifier, bool>(DemoModeNotifier.new);

/// Scope for on-device employee data: the environment id, or `demo` during a
/// demo session, so demo records never mix with real ones.
final dataScopeProvider = Provider<String>(
  (ref) => ref.watch(isDemoSessionProvider) ? 'demo' : ref.watch(activeEnvironmentProvider).environmentId,
);

/// Recent requests (admin builds; the recorder isn't installed otherwise).
final networkLogProvider = Provider<NetworkLog>((ref) {
  final log = NetworkLog();
  ref.onDispose(log.dispose);
  return log;
});

/// HTTP client bound to the active environment. Recreated (and the old one
/// closed, cancelling in-flight requests) whenever the environment changes.
final apiClientProvider = Provider<ApiClient>((ref) {
  final env = ref.watch(activeEnvironmentProvider);
  final authHeader = ref.watch(authHeaderProvider);
  var disposed = false;
  final dio = ref.watch(dioFactoryProvider)();
  // Demo sessions talk to the in-app demo server, never to a real backend.
  // The branch is compiled out of production builds.
  if (!kProductionBuild && ref.watch(isDemoSessionProvider)) {
    dio.httpClientAdapter = DemoBackendAdapter(ref.watch(localDatabaseProvider).box(BoxNames.demoBackend));
  }
  // Admin builds only: the request recorder is not even installed in client
  // (production) builds.
  if (ref.watch(appFeaturesProvider).networkInspector) {
    dio.interceptors.add(NetworkRecorderInterceptor(ref.watch(networkLogProvider)));
  }
  final client = ApiClient(
    environment: env,
    dio: dio,
    authHeader: authHeader,
    logRequests: kDebugMode && env.allowDebugFeatures,
    onReachable: () {
      if (!disposed) ref.read(connectionStatusProvider.notifier).markReachable(env.environmentId);
    },
    onUnauthorized: () {
      if (!disposed) ref.read(authControllerProvider.notifier).sessionExpired();
    },
    onUnreachable: (e) {
      if (!disposed) {
        ref.read(connectionStatusProvider.notifier).markUnreachable(env.environmentId, ApiException.fromDio(e).message);
      }
    },
  );
  ref.onDispose(() {
    disposed = true;
    client.close();
  });
  return client;
});
