import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_endpoints.dart';
import '../../core/network/api_exceptions.dart';
import '../../core/services/providers.dart';
import '../environments/presentation/providers/environment_providers.dart';
import 'app_features_provider.dart';

/// What kind of network the device has. This alone never means "online":
/// Wi-Fi can be up while the backend is unreachable.
enum DeviceNetwork {
  wifi('Wi-Fi'),
  ethernet('Ethernet'),
  mobile('Mobile data'),
  other('Connected'),
  none('No network'),

  /// The platform cannot tell (e.g. some browsers). Treated as connected.
  unknown('Network');

  const DeviceNetwork(this.label);
  final String label;

  bool get hasNetwork => this != none;

  /// For "sync on Wi-Fi only". Unknown is allowed (web can't report it).
  bool get isUnmetered => this == wifi || this == ethernet || this == unknown;

  static DeviceNetwork fromResults(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return wifi;
    if (results.contains(ConnectivityResult.ethernet)) return ethernet;
    if (results.contains(ConnectivityResult.mobile)) return mobile;
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) return none;
    return other;
  }
}

/// Device connectivity from connectivity_plus. Overridden in tests.
final deviceNetworkProvider = StreamProvider<DeviceNetwork>((ref) async* {
  final connectivity = Connectivity();
  try {
    yield DeviceNetwork.fromResults(await connectivity.checkConnectivity());
  } catch (_) {
    yield DeviceNetwork.unknown; // plugin unavailable: let backend checks decide
  }
  try {
    await for (final r in connectivity.onConnectivityChanged) {
      yield DeviceNetwork.fromResults(r);
    }
  } catch (_) {
    // No change events on this platform.
  }
});

/// Backend reachability check timing.
@immutable
class ConnectivityConfig {
  const ConnectivityConfig({
    this.monitor = true,
    this.onlineInterval = const Duration(seconds: 60),
    this.minBackoff = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 2),
  });

  /// Run periodic checks (disabled in widget tests).
  final bool monitor;

  /// Interval between checks while the server is reachable.
  final Duration onlineInterval;

  /// Retry delays while the server is unreachable: min · 2^(n-1), capped.
  final Duration minBackoff;
  final Duration maxBackoff;

  Duration backoff(int failures) {
    final n = math.max(1, failures);
    final ms = minBackoff.inMilliseconds * math.pow(2, math.min(n - 1, 10));
    return Duration(milliseconds: math.min(ms.toInt(), maxBackoff.inMilliseconds));
  }
}

final connectivityConfigProvider = Provider<ConnectivityConfig>((ref) {
  final features = ref.watch(appFeaturesProvider);
  final seconds = ref.watch(settingsProvider.select((s) => s.connectionCheckSeconds));
  return ConnectivityConfig(
    onlineInterval: features.connectionIntervalSetting ? Duration(seconds: seconds) : const Duration(seconds: 60),
  );
});

/// What the user sees.
enum NetworkStatus {
  checking('Checking…'),
  online('Online'),
  offline('Offline'),
  serverUnavailable('Server unavailable');

  const NetworkStatus(this.label);
  final String label;
}

@immutable
class ConnectionStatus {
  const ConnectionStatus({
    required this.environmentId,
    this.device = DeviceNetwork.unknown,
    this.backendReachable,
    this.checking = false,
    this.lastSuccessAt,
    this.lastCheckedAt,
    this.message,
    this.failures = 0,
  });

  final String environmentId;
  final DeviceNetwork device;

  /// `null` until the first check (or API call) completes.
  final bool? backendReachable;
  final bool checking;
  final DateTime? lastSuccessAt;
  final DateTime? lastCheckedAt;
  final String? message;

  /// Consecutive failed checks (drives the retry backoff).
  final int failures;

  NetworkStatus get status {
    if (!device.hasNetwork) return NetworkStatus.offline;
    if (backendReachable == true) return NetworkStatus.online;
    // While re-checking after a failure, keep showing "Server unavailable"
    // rather than flickering to "Checking".
    if (backendReachable == false) return NetworkStatus.serverUnavailable;
    return NetworkStatus.checking;
  }

  bool get isOnline => status == NetworkStatus.online;

  /// Whether an upload is worth attempting now. Unknown counts as "try":
  /// a failed attempt falls back to saving on the device anyway.
  bool get shouldAttemptServer => device.hasNetwork && backendReachable != false;

  ConnectionStatus copyWith({
    DeviceNetwork? device,
    bool? Function()? backendReachable,
    bool? checking,
    DateTime? lastSuccessAt,
    DateTime? lastCheckedAt,
    String? Function()? message,
    int? failures,
  }) => ConnectionStatus(
    environmentId: environmentId,
    device: device ?? this.device,
    backendReachable: backendReachable == null ? this.backendReachable : backendReachable(),
    checking: checking ?? this.checking,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    message: message == null ? this.message : message(),
    failures: failures ?? this.failures,
  );
}

/// Two-level connectivity monitor:
/// 1. device network (connectivity_plus events), and
/// 2. backend reachability — a low-impact `GET /api/employee/list?size=1`
///    (the backend has no health endpoint), repeated every
///    [ConnectivityConfig.onlineInterval] while online and with exponential
///    backoff while unreachable. No checks run while the device has no
///    network; one runs as soon as the network returns.
///
/// Every real API call also updates the status (via the HTTP client's
/// interceptor), so checks rarely need to hit the network on their own.
class ConnectionStatusNotifier extends Notifier<ConnectionStatus> {
  final _lastSuccess = <String, DateTime>{};
  Timer? _timer;
  bool _inFlight = false;

  ConnectivityConfig get _config => ref.read(connectivityConfigProvider);

  @override
  ConnectionStatus build() {
    final env = ref.watch(activeEnvironmentProvider);
    final config = ref.watch(connectivityConfigProvider);
    ref.onDispose(() => _timer?.cancel());
    ref.listen<AsyncValue<DeviceNetwork>>(deviceNetworkProvider, (_, next) {
      final d = next.valueOrNull;
      if (d != null) _onDevice(d);
    });
    final device = ref.read(deviceNetworkProvider).valueOrNull ?? DeviceNetwork.unknown;
    if (config.monitor) scheduleMicrotask(check);
    return ConnectionStatus(
      environmentId: env.environmentId,
      device: device,
      lastSuccessAt: _lastSuccess[env.environmentId],
    );
  }

  void _onDevice(DeviceNetwork d) {
    final before = state.device;
    if (d == before) return;
    state = state.copyWith(device: d);
    if (!d.hasNetwork) {
      _timer?.cancel();
    } else if (!before.hasNetwork) {
      state = state.copyWith(failures: 0);
      check();
    }
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    if (!_config.monitor || !state.device.hasNetwork) return;
    _timer = Timer(after, check);
  }

  void markReachable(String environmentId) {
    if (environmentId != state.environmentId) return;
    final now = DateTime.now();
    _lastSuccess[environmentId] = now;
    state = state.copyWith(
      backendReachable: () => true,
      checking: false,
      lastSuccessAt: now,
      lastCheckedAt: now,
      message: () => null,
      failures: 0,
    );
    _schedule(_config.onlineInterval);
  }

  void markUnreachable(String environmentId, String message) {
    if (environmentId != state.environmentId) return;
    final failures = state.failures + 1;
    state = state.copyWith(
      backendReachable: () => false,
      checking: false,
      lastCheckedAt: DateTime.now(),
      message: () => message,
      failures: failures,
    );
    _schedule(_config.backoff(failures));
  }

  /// Checks the backend now (also used by "Retry connection").
  Future<void> check() async {
    if (_inFlight) return;
    if (!state.device.hasNetwork) {
      state = state.copyWith(checking: false, lastCheckedAt: DateTime.now());
      return;
    }
    _inFlight = true;
    final env = state.environmentId;
    state = state.copyWith(checking: true);
    try {
      await ref.read(apiClientProvider).get(ApiEndpoints.employeeList, query: const {'page': 0, 'size': 1});
      markReachable(env);
    } on ApiException catch (e) {
      if (e.statusCode > 0 && !e.isNetwork) {
        markReachable(env); // the server answered
      } else {
        markUnreachable(env, e.message);
      }
    } catch (_) {
      markUnreachable(env, 'Unable to connect to the server.');
    } finally {
      _inFlight = false;
    }
  }
}

final connectionStatusProvider = NotifierProvider<ConnectionStatusNotifier, ConnectionStatus>(
  ConnectionStatusNotifier.new,
);

/// Convenience: just the user-facing status (rebuilds only when it changes).
final networkStatusProvider = Provider<NetworkStatus>(
  (ref) => ref.watch(connectionStatusProvider.select((s) => s.status)),
);
