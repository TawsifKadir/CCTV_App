import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cctv_app/core/config/app_environment.dart';
import 'package:cctv_app/core/config/environment_registry.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/data/local/local_database.dart';
import 'package:cctv_app/data/models/operator.dart';
import 'package:cctv_app/features/authentication/data/auth_session.dart';
import 'package:cctv_app/features/authentication/data/session_store.dart';
import 'package:cctv_app/features/authentication/providers/auth_controller.dart';
import 'package:cctv_app/core/services/app_notifier.dart';
import 'package:cctv_app/features/connectivity/connectivity_service.dart';
import 'package:cctv_app/features/environments/presentation/providers/environment_providers.dart';
import 'package:cctv_app/features/sync/presentation/sync_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show GlobalKey, ScaffoldMessengerState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fake HTTP transport for Dio: records every request and answers with
/// [handler]. Lets tests exercise the real ApiClient, interceptors, JSON
/// decoding and error mapping without a server.
class FakeBackend implements HttpClientAdapter {
  FakeBackend([FutureOr<ResponseBody> Function(RequestOptions o)? handler]) : handler = handler ?? defaultHandler;

  FutureOr<ResponseBody> Function(RequestOptions o) handler;
  final requests = <RequestOptions>[];

  RequestOptions get last => requests.last;
  List<RequestOptions> get listRequests => requests.where((r) => r.path.endsWith('/employee/list')).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) await requestStream.drain<void>();
    return handler(options);
  }

  @override
  void close({bool force = false}) {}

  /// Answers list requests with [samplePage] and registrations with 201.
  static FutureOr<ResponseBody> defaultHandler(RequestOptions o) {
    if (o.path.endsWith('/auth/login')) return fakeLogin(o);
    if (o.path.endsWith('/employee/add')) return json(201, {...sampleEmployeeJson(), 'liveWatchList': true});
    final q = o.queryParameters;
    return json(200, samplePage(page: (q['page'] as int?) ?? 0, size: (q['size'] as int?) ?? 24, total: 30));
  }
}

ResponseBody json(int status, Object? body) => ResponseBody.fromString(
  body == null ? '' : jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ResponseBody text(int status, String body) => ResponseBody.fromString(body, status);

const testUsername = 'admin';
const testPassword = 'Admin@123';

/// Stand-in for POST /api/auth/login with the confirmed response shape and
/// Spring's cookie CSRF: without a matching X-XSRF-TOKEN it answers 403 and
/// issues a token (like the real server).
ResponseBody fakeLogin(RequestOptions o) {
  const xsrf = 'csrf-abc';
  if (o.headers['X-XSRF-TOKEN'] != xsrf || !(o.headers['Cookie']?.toString().contains('XSRF-TOKEN=$xsrf') ?? false)) {
    return ResponseBody.fromString(
      jsonEncode({'status': 403, 'error': 'Forbidden', 'timestamp': 'x'}),
      403,
      headers: {
        'set-cookie': ['XSRF-TOKEN=$xsrf; Path=/'],
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
  final body = o.data is Map ? o.data as Map : const {};
  if (body['username'] == testUsername && body['password'] == testPassword) {
    return json(200, {'token': 'tok-123', 'role': 'admin', 'username': 'admin', 'expiresIn': 1800});
  }
  return json(401, {'message': 'Invalid username or password.'});
}

/// A signed-in session for the test environment.
AuthSession testSession({String environmentId = 'local'}) => AuthSession(
  operator: const Operator(username: 'admin', displayName: 'Admin User'),
  environmentId: environmentId,
  createdAt: DateTime(2026, 11, 17),
  accessToken: 'tok-123',
  tokenType: 'Bearer',
);

Map<String, dynamic> sampleEmployeeJson({
  int id = 1,
  String name = 'Example Employee',
  String? photoUrl,
  String source = 'photo',
}) => {
  'id': id,
  'employeeNo': 1000 + id,
  'name': name,
  'dateOfBirth': '1998-05-20',
  'designation': 'Software Engineer',
  'templateId': 'template-$id',
  'templateBytes': 2048,
  'enrolledAt': '2026-11-16T10:30:00',
  'photoUrl': photoUrl,
  'enrollmentSource': source,
};

Map<String, dynamic> samplePage({int page = 0, int size = 24, int total = 30}) {
  final totalPages = total == 0 ? 0 : (total + size - 1) ~/ size;
  final start = page * size;
  final count = (total - start).clamp(0, size);
  return {
    'content': [
      for (var i = 0; i < count; i++) sampleEmployeeJson(id: start + i + 1, name: 'Employee ${start + i + 1}'),
    ],
    'page': page,
    'size': size,
    'totalElements': total,
    'totalPages': totalPages,
    'hasPrevious': page > 0,
    'hasNext': page + 1 < totalPages,
  };
}

/// Local build environment for tests (web-style localhost).
BuildEnvironment testBuildEnvironment({String appEnv = 'local', String? apiBaseUrl, bool allowSwitching = true}) =>
    resolveBuildEnvironment(
      appEnv: appEnv,
      flavor: '',
      apiBaseUrlOverride: apiBaseUrl ?? '',
      localHostOverride: '',
      allowSwitching: allowSwitching,
      platform: const PlatformInfo(isWeb: true, platform: TargetPlatform.linux),
    );

/// Real Hive storage in a throwaway directory + a Riverpod container wired
/// like the app, with a [FakeBackend] behind the HTTP client.
/// Device network the tests control (Wi-Fi by default).
class FakeDeviceNetwork {
  FakeDeviceNetwork([this.current = DeviceNetwork.wifi]);
  DeviceNetwork current;
  final _controller = StreamController<DeviceNetwork>.broadcast();

  Stream<DeviceNetwork> stream() async* {
    yield current;
    yield* _controller.stream;
  }

  void set(DeviceNetwork d) {
    current = d;
    _controller.add(d);
  }
}

/// Overrides shared by unit and widget tests: fake HTTP, controllable
/// device network, no periodic connectivity timers, captured notifications.
List<Override> testOverrides({
  required FakeBackend backend,
  required FakeDeviceNetwork network,
  required AppNotifier notifier,
  BuildEnvironment? environment,
  SessionStore? sessionStore,
}) => [
  sessionStoreProvider.overrideWithValue(sessionStore ?? MemorySessionStore()),
  buildEnvironmentProvider.overrideWithValue(environment ?? testBuildEnvironment()),
  dioFactoryProvider.overrideWithValue(() => Dio()..httpClientAdapter = backend),
  deviceNetworkProvider.overrideWith((ref) => network.stream()),
  connectivityConfigProvider.overrideWithValue(const ConnectivityConfig(monitor: false)),
  appNotifierProvider.overrideWithValue(notifier),
];

class TestEnv {
  TestEnv._(this.dir, this.db, this.container, this.backend, this.network, this.notifier, this.sessions);

  final Directory dir;
  final LocalDatabase db;
  final ProviderContainer container;
  final FakeBackend backend;
  final FakeDeviceNetwork network;
  final AppNotifier notifier;
  final MemorySessionStore sessions;

  static Future<TestEnv> create({
    FakeBackend? backend,
    BuildEnvironment? environment,
    Directory? reuse,
    MemorySessionStore? sessions,
    AuthSession? initialSession,
  }) async {
    final dir = reuse ?? await Directory.systemTemp.createTemp('enrolly_test_');
    final db = await LocalDatabase.open(path: dir.path);
    final fake = backend ?? FakeBackend();
    final network = FakeDeviceNetwork();
    final notifier = AppNotifier(key: GlobalKey<ScaffoldMessengerState>(), dedupeWindow: Duration.zero);
    final store = sessions ?? MemorySessionStore();
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        initialSessionProvider.overrideWithValue(initialSession),
        ...testOverrides(
          backend: fake,
          network: network,
          notifier: notifier,
          environment: environment,
          sessionStore: store,
        ),
      ],
    );
    // Start the device-network stream so the connection status sees it.
    container.listen(deviceNetworkProvider, (_, _) {});
    await container.read(deviceNetworkProvider.future);
    return TestEnv._(dir, db, container, fake, network, notifier, store);
  }

  /// Lets queued microtasks and Hive writes settle.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  T read<T>(ProviderListenable<T> p) => container.read(p);

  /// Closes storage but keeps files, to simulate an app restart.
  Future<void> close() async {
    container.dispose();
    await db.close();
  }

  Future<void> dispose() async {
    await close();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Bytes with a JPEG signature (only the signature is validated client-side).
Uint8List fakeJpeg([int size = 2048]) {
  final b = Uint8List(size);
  b.setAll(0, [0xFF, 0xD8, 0xFF, 0xE0]);
  return b;
}

Uint8List fakePng([int size = 2048]) {
  final b = Uint8List(size);
  b.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return b;
}

/// A stateful fake of the Spring Boot employee API: registrations are
/// stored and returned by the list endpoint (with search, source filter and
/// paging), like the real backend. Switches simulate failures.
class FakeServer {
  final employees = <Map<String, dynamic>>[];
  int _nextId = 1;
  int postCount = 0;

  /// Transport failure before reaching the server (nothing saved).
  bool down = false;

  /// The server saves the employee but the response never arrives.
  bool dropResponseAfterSave = false;

  /// Respond to POST with a receive timeout after saving.
  bool timeoutAfterSave = false;

  /// Names the server rejects with 400 (e.g. no face found).
  final rejectNames = <String>{};

  late final FakeBackend backend = FakeBackend(_handle);

  FutureOr<ResponseBody> _handle(RequestOptions o) {
    if (down) throw const SocketException('Connection refused');
    if (o.path.endsWith('/auth/login')) return fakeLogin(o);
    if (o.path.endsWith('/employee/add')) {
      postCount++;
      final form = o.data as FormData;
      final fields = {for (final f in form.fields) f.key: f.value};
      if (rejectNames.contains(fields['name'])) {
        return json(400, {'error': 'No face could be detected in the photo.'});
      }
      final id = _nextId++;
      final e = {
        'id': id,
        'employeeNo': 1000 + id,
        'name': fields['name'],
        'dateOfBirth': fields['dateOfBirth'],
        'designation': fields['designation'],
        'templateId': 'tpl-$id',
        'templateBytes': 2048,
        'enrolledAt': DateTime(2026, 11, 16, 9).add(Duration(minutes: id)).toIso8601String(),
        'photoUrl': '/api/employee/$id/photo',
        'enrollmentSource': 'photo',
      };
      employees.add(e);
      if (dropResponseAfterSave) throw const SocketException('Connection reset by peer');
      if (timeoutAfterSave) throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout);
      return json(201, {...e, 'liveWatchList': true});
    }
    final q = o.queryParameters;
    final page = (q['page'] as int?) ?? 0;
    final size = (q['size'] as int?) ?? 24;
    final text = (q['query'] as String?)?.toLowerCase();
    final source = q['source'] as String?;
    final matches = employees.reversed.where((e) {
      if (source != null && e['enrollmentSource'] != source) return false;
      return text == null || (e['name'] as String).toLowerCase().contains(text);
    }).toList();
    final totalPages = matches.isEmpty ? 0 : (matches.length + size - 1) ~/ size;
    return json(200, {
      'content': matches.skip(page * size).take(size).toList(),
      'page': page,
      'size': size,
      'totalElements': matches.length,
      'totalPages': totalPages,
      'hasPrevious': page > 0,
      'hasNext': page + 1 < totalPages,
    });
  }
}
