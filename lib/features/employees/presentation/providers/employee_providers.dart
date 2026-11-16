
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../../core/services/providers.dart';
import '../../../connectivity/connectivity_service.dart';
import '../../../environments/presentation/providers/environment_providers.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_page.dart';
import '../../data/models/employee_query.dart';
import '../../data/models/employee_record.dart';
import '../../data/models/local_employee.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/local_employee_repository.dart';
import '../../data/repositories/server_employee_cache.dart';
import '../../data/services/employee_api_service.dart';

/// Cache writes never block showing fresh server data; a failed write only
/// means the offline copy is a little older.
void _cacheInBackground(Future<void> write) => unawaited(write.catchError((Object e) {
      debugPrint('Employee cache write failed: $e');
    }));

// ---------------------------------------------------------------------------
// Data sources (one instance per environment)
// ---------------------------------------------------------------------------

final employeeApiServiceProvider = Provider<EmployeeApiService>(
  (ref) => EmployeeApiService(ref.watch(apiClientProvider)),
);

/// Server access with a short-lived page cache (per environment).
final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => EmployeeRepository(api: ref.watch(employeeApiServiceProvider)),
);

/// Employees registered on this device (persistent).
final localEmployeeRepositoryProvider = Provider<LocalEmployeeRepository>((ref) {
  final db = ref.watch(localDatabaseProvider);
  return LocalEmployeeRepository(
    records: db.box(BoxNames.localEmployees),
    photos: db.lazyBox(BoxNames.localEmployeePhotos),
    environmentId: ref.watch(activeEnvironmentProvider).environmentId,
  );
});

/// Server records seen on this device, for offline browsing.
final serverEmployeeCacheProvider = Provider<ServerEmployeeCache>((ref) => ServerEmployeeCache(
      ref.watch(localDatabaseProvider).box(BoxNames.serverEmployeeCache),
      environmentId: ref.watch(activeEnvironmentProvider).environmentId,
    ));

/// Live list of local records; updates on every change (registration, sync
/// state transitions).
class LocalEmployeesNotifier extends Notifier<List<LocalEmployee>> {
  @override
  List<LocalEmployee> build() {
    final repo = ref.watch(localEmployeeRepositoryProvider);
    final sub = repo.changes.listen((_) => state = repo.all());
    ref.onDispose(sub.cancel);
    return repo.all();
  }
}

final localEmployeesProvider = NotifierProvider<LocalEmployeesNotifier, List<LocalEmployee>>(LocalEmployeesNotifier.new);

/// Photo of a locally registered employee (loaded on demand).
final localPhotoProvider = FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, photoRef) => ref.watch(localEmployeeRepositoryProvider).loadPhoto(photoRef),
);

/// Counts by sync state (this environment).
@immutable
class LocalCounts {
  const LocalCounts({
    this.total = 0,
    this.localOnly = 0,
    this.pending = 0,
    this.syncing = 0,
    this.failed = 0,
    this.synced = 0,
    this.needsReview = 0,
  });
  final int total;
  final int localOnly;
  final int pending;
  final int syncing;
  final int failed;
  final int synced;
  final int needsReview;

  /// Not yet on the server.
  int get awaiting => localOnly + pending + syncing + failed;

  factory LocalCounts.of(List<LocalEmployee> items) {
    var lo = 0, p = 0, sy = 0, f = 0, s = 0, r = 0;
    for (final e in items) {
      switch (e.syncStatus) {
        case SyncStatus.localOnly:
          lo++;
        case SyncStatus.pendingSync:
          p++;
        case SyncStatus.syncing:
          sy++;
        case SyncStatus.failed:
          f++;
          if (e.needsReconciliation) r++;
        case SyncStatus.synced:
          s++;
      }
    }
    return LocalCounts(total: items.length, localOnly: lo, pending: p, syncing: sy, failed: f, synced: s, needsReview: r);
  }
}

final localCountsProvider = Provider<LocalCounts>((ref) => LocalCounts.of(ref.watch(localEmployeesProvider)));

// ---------------------------------------------------------------------------
// Employee list query & filters
// ---------------------------------------------------------------------------

/// Server query (page, search, source). Reset when the environment changes.
class EmployeeQueryNotifier extends Notifier<EmployeeQuery> {
  @override
  EmployeeQuery build() {
    ref.watch(activeEnvironmentProvider);
    return const EmployeeQuery();
  }

  void setSearch(String text) {
    if (text.trim() == state.query.trim()) return;
    state = state.copyWith(query: text, page: 0);
  }

  void setSource(EnrollmentSource? source) {
    if (source == state.source) return;
    state = state.copyWith(source: () => source, page: 0);
  }

  void goToPage(int page) {
    if (page < 0 || page == state.page) return;
    state = state.copyWith(page: page);
  }

  void reset() => state = const EmployeeQuery();
}

final employeeQueryProvider = NotifierProvider<EmployeeQueryNotifier, EmployeeQuery>(EmployeeQueryNotifier.new);

class RecordFilterNotifier extends Notifier<RecordFilter> {
  @override
  RecordFilter build() {
    ref.watch(activeEnvironmentProvider);
    return RecordFilter.all;
  }

  void set(RecordFilter f) => state = f;
}

final recordFilterProvider = NotifierProvider<RecordFilterNotifier, RecordFilter>(RecordFilterNotifier.new);

/// Server part of the listing.
@immutable
class ServerListing {
  const ServerListing({required this.page, required this.fromCache, this.lastRefresh, this.error});

  final EmployeePage page;

  /// Served from the device cache (offline or server error) — show
  /// "Last updated" and never present it as live.
  final bool fromCache;
  final DateTime? lastRefresh;

  /// Why the live request failed, if it did.
  final Object? error;
}

/// Fetches the current server page when the server is reachable; otherwise
/// (or on failure) answers the same query from cached server records.
/// Re-runs automatically when reachability changes.
final serverPageProvider = FutureProvider<ServerListing?>((ref) async {
  if (ref.watch(recordFilterProvider).isLocal) return null;
  final query = ref.watch(employeeQueryProvider);
  final repo = ref.watch(employeeRepositoryProvider);
  final cache = ref.watch(serverEmployeeCacheProvider);
  final tryServer = ref.watch(connectionStatusProvider.select((s) => s.shouldAttemptServer));
  ServerListing fromCache([Object? error]) =>
      ServerListing(page: cache.query(query), fromCache: true, lastRefresh: cache.lastRefresh, error: error);
  if (!tryServer) return fromCache();
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  try {
    final page = await repo.getEmployees(query, cancelToken: cancel);
    _cacheInBackground(cache.upsertPage(page, query));
    return ServerListing(page: page, fromCache: false, lastRefresh: DateTime.now());
  } on ApiException catch (e) {
    if (e.kind == ApiErrorKind.cancelled) rethrow;
    final cached = fromCache(e);
    // Nothing cached and a server-side error: surface it as an error state.
    if (cached.page.totalElements == 0 && !e.isNetwork) rethrow;
    return cached;
  }
});

/// The unified list shown on the Employees screen.
@immutable
class EmployeeListing {
  const EmployeeListing({required this.localRecords, required this.server, required this.filter});

  /// Device records not yet on the server (shown above server records on the
  /// first page). Not paginated: they are few and must never be hidden.
  final List<EmployeeRecord> localRecords;

  /// Server page (live or cached); `null` for device-only filters.
  final AsyncValue<ServerListing?> server;
  final RecordFilter filter;

  List<EmployeeRecord> serverRecords(Map<int, LocalEmployee> linked) => [
        for (final e in server.valueOrNull?.page.content ?? const <Employee>[])
          EmployeeRecord(server: e, local: e.id == null ? null : linked[e.id]),
      ];
}

final employeeListingProvider = Provider<EmployeeListing>((ref) {
  final filter = ref.watch(recordFilterProvider);
  final query = ref.watch(employeeQueryProvider);
  final locals = ref.watch(localEmployeesProvider);
  final text = query.query.trim().toLowerCase();
  // Registrations through POST /employee/add are recorded by the backend as
  // "photo" enrolments, so device records match the Photo Upload filter.
  final sourceOk = query.source == null || query.source == EnrollmentSource.photo;
  final showLocal = filter != RecordFilter.onServer && sourceOk && (filter.isLocal || query.page == 0);
  final localRecords = !showLocal
      ? const <EmployeeRecord>[]
      : [
          for (final e in locals)
            if (e.isUnsynced && filter.matches(e.syncStatus) && (text.isEmpty || matchesSearch(e.toEmployee(), text)))
              EmployeeRecord(local: e),
        ];
  return EmployeeListing(
    localRecords: localRecords,
    server: filter.isLocal ? const AsyncData(null) : ref.watch(serverPageProvider),
    filter: filter,
  );
});

/// Server id → local record, for records this device registered.
final linkedLocalByServerIdProvider = Provider<Map<int, LocalEmployee>>((ref) => {
      for (final e in ref.watch(localEmployeesProvider))
        if (e.serverId != null) e.serverId!: e,
    });

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

@immutable
class ServerOverview {
  const ServerOverview({required this.total, required this.latest, required this.fromCache, this.lastRefresh, this.error});

  /// Employees on the server (`null` = unknown).
  final int? total;
  final List<Employee> latest;
  final bool fromCache;
  final DateTime? lastRefresh;
  final Object? error;
}

final serverOverviewProvider = FutureProvider<ServerOverview>((ref) async {
  final repo = ref.watch(employeeRepositoryProvider);
  final cache = ref.watch(serverEmployeeCacheProvider);
  final tryServer = ref.watch(connectionStatusProvider.select((s) => s.shouldAttemptServer));
  ServerOverview cached([Object? error]) => ServerOverview(
        total: cache.lastKnownTotal,
        latest: cache.all().take(6).toList(),
        fromCache: true,
        lastRefresh: cache.lastRefresh,
        error: error,
      );
  if (!tryServer) return cached();
  try {
    const q = EmployeeQuery(page: 0, size: 6);
    final page = await repo.getEmployees(q);
    _cacheInBackground(cache.upsertPage(page, q));
    return ServerOverview(total: page.totalElements, latest: page.content, fromCache: false, lastRefresh: DateTime.now());
  } on ApiException catch (e) {
    return cached(e);
  }
});

/// Server count per enrolment source (admin dashboard). `null` offline.
final employeeCountBySourceProvider = FutureProvider.family<int?, EnrollmentSource>((ref, source) async {
  final repo = ref.watch(employeeRepositoryProvider);
  if (!ref.watch(connectionStatusProvider.select((s) => s.shouldAttemptServer))) return null;
  final page = await repo.getEmployees(EmployeeQuery(page: 0, size: 1, source: source));
  return page.totalElements;
});

/// Drops cached pages and refetches everything employee-related.
final employeeRefresherProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(employeeRepositoryProvider).invalidate();
    ref.invalidate(serverPageProvider);
    ref.invalidate(serverOverviewProvider);
    ref.invalidate(employeeCountBySourceProvider);
  };
});

/// Finds a record by its list key — from the current page, device records
/// or the persistent server cache (so profiles survive a browser refresh).
final employeeRecordProvider = Provider.family<EmployeeRecord?, String>((ref, key) {
  final locals = ref.watch(localEmployeesProvider);
  if (key.startsWith('l:')) {
    final id = key.substring(2);
    for (final e in locals) {
      if (e.localId == id) {
        // Once synced, show it as a server record with its local data.
        final server = e.serverId == null ? null : ref.watch(serverEmployeeCacheProvider).byId(e.serverId!);
        return server == null && e.isUnsynced ? EmployeeRecord(local: e) : EmployeeRecord(server: server ?? e.toEmployee(), local: e);
      }
    }
    return null;
  }
  final id = int.tryParse(key);
  final linked = ref.watch(linkedLocalByServerIdProvider);
  for (final e in ref.watch(serverPageProvider).valueOrNull?.page.content ?? const <Employee>[]) {
    if (e.key == key) return EmployeeRecord(server: e, local: e.id == null ? null : linked[e.id]);
  }
  if (id == null) return null;
  final cached = ref.watch(serverEmployeeCacheProvider).byId(id);
  if (cached != null) return EmployeeRecord(server: cached, local: linked[id]);
  final local = linked[id];
  return local == null ? null : EmployeeRecord(server: local.toEmployee(), local: local);
});
