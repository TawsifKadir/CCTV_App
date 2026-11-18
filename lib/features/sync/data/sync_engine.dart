import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../employees/data/models/employee.dart';
import '../../employees/data/models/employee_query.dart';
import '../../employees/data/models/local_employee.dart';
import '../../employees/data/models/registration_result.dart';
import '../../employees/data/repositories/local_employee_repository.dart';
import '../../employees/data/repositories/server_employee_cache.dart';
import '../../employees/data/services/employee_api_service.dart';
import '../../registration/domain/employee_registration.dart';
import 'package:dio/dio.dart' show ProgressCallback;
import 'sync_history.dart';

enum UploadOutcome { uploaded, alreadySynced, failed, uncertain, skipped }

@immutable
class RecordSyncResult {
  const RecordSyncResult(this.outcome, {this.record, this.message, this.networkDown = false, this.result});
  final UploadOutcome outcome;
  final LocalEmployee? record;
  final String? message;

  /// The server became unreachable: a batch should stop here.
  final bool networkDown;
  final RegistrationResult? result;
}

@immutable
class SyncProgress {
  const SyncProgress({required this.done, required this.total, this.current});
  final int done;
  final int total;
  final String? current;
}

/// Which local records a run picks up.
enum SyncSelection {
  /// Automatic sync: pending/local-only records, plus transient failures
  /// whose backoff has elapsed. Skips records the server rejected.
  automatic,

  /// "Sync now": every unsynced record except ones the server rejected.
  manual,

  /// "Retry failed": every failed record, including rejected ones.
  failedOnly,
}

/// Uploads locally stored registrations to `POST /api/employee/add`.
///
/// Duplicate safety (the backend has no idempotency key yet):
/// 1. A record is marked SYNCING and persisted *before* the request.
/// 2. Only one upload per record can run at a time, and only one batch at
///    a time (single-flight).
/// 3. The server's response is persisted immediately (SYNCED + server id).
/// 4. If the outcome is uncertain — timeout after sending, dropped
///    connection, 5xx, browser-blocked response, or the app closing
///    mid-upload — the record is marked FAILED + needs review instead of
///    being retried blindly. Before any retry, the engine searches the
///    server (`GET /api/employee/list?query=<name>`) for an unlinked
///    employee with the same name, date of birth and designation; if found
///    it links to it instead of uploading again.
///
/// This greatly reduces, but cannot fully guarantee, duplicate prevention:
/// an identical-looking employee registered elsewhere would be linked, and
/// a matching record created later could be missed. A client-generated
/// external ID accepted by the backend would make this exact.
class SyncEngine {
  SyncEngine({
    required this.local,
    required this.api,
    required this.history,
    required this.cache,
    DateTime Function()? clock,
    this.minRetry = const Duration(seconds: 30),
    this.maxRetry = const Duration(minutes: 30),
  }) : _clock = clock ?? DateTime.now;

  final LocalEmployeeRepository local;
  final EmployeeApiService api;
  final SyncHistoryRepository history;
  final ServerEmployeeCache cache;
  final DateTime Function() _clock;
  final Duration minRetry;
  final Duration maxRetry;
  static const _uuid = Uuid();

  final _inFlight = <String>{};
  Future<SyncRun>? _running;

  bool get isRunning => _running != null;
  bool isUploading(String localId) => _inFlight.contains(localId);

  /// Records left in SYNCING by an interrupted run (app closed or crashed
  /// mid-upload) have an unknown outcome: mark them for review.
  Future<int> recoverInterrupted() async {
    var n = 0;
    for (final e in local.all()) {
      if (e.syncStatus == SyncStatus.syncing && !_inFlight.contains(e.localId)) {
        await local.update(
          e.localId,
          (x) => x.copyWith(
            syncStatus: SyncStatus.failed,
            needsReconciliation: true,
            syncError: () => 'The upload was interrupted. The server will be checked before retrying.',
          ),
        );
        n++;
      }
    }
    return n;
  }

  Duration retryDelay(int attempts) {
    final ms = minRetry.inMilliseconds * math.pow(2, math.max(0, math.min(attempts - 1, 12)));
    return Duration(milliseconds: math.min(ms.toInt(), maxRetry.inMilliseconds));
  }

  bool _selected(LocalEmployee e, SyncSelection s, DateTime now) {
    if (e.isTestData || !e.isUnsynced || _inFlight.contains(e.localId)) return false;
    switch (s) {
      case SyncSelection.failedOnly:
        return e.syncStatus == SyncStatus.failed;
      case SyncSelection.manual:
        return !e.permanentFailure;
      case SyncSelection.automatic:
        if (e.permanentFailure) return false;
        if (e.syncStatus == SyncStatus.failed) return e.nextRetryAt == null || !now.isBefore(e.nextRetryAt!);
        return true;
    }
  }

  /// Records a run would pick up right now.
  List<LocalEmployee> candidates(SyncSelection s) {
    final now = _clock();
    return local.all().reversed.where((e) => _selected(e, s, now)).toList(); // oldest first
  }

  /// Runs a batch. Concurrent calls share the running batch.
  Future<SyncRun> run(
    SyncSelection selection, {
    required SyncTrigger trigger,
    void Function(SyncProgress)? onProgress,
  }) {
    final existing = _running;
    if (existing != null) return existing;
    final f = _runBatch(selection, trigger, onProgress);
    _running = f;
    return f.whenComplete(() => _running = null);
  }

  Future<SyncRun> _runBatch(
    SyncSelection selection,
    SyncTrigger trigger,
    void Function(SyncProgress)? onProgress,
  ) async {
    final started = _clock();
    final items = candidates(selection);
    var uploaded = 0, failed = 0, already = 0, uncertain = 0;
    var aborted = false;
    final logs = <SyncRecordLog>[];
    for (var i = 0; i < items.length; i++) {
      onProgress?.call(SyncProgress(done: i, total: items.length, current: items[i].name));
      final r = await syncRecord(items[i].localId);
      switch (r.outcome) {
        case UploadOutcome.uploaded:
          uploaded++;
        case UploadOutcome.alreadySynced:
          already++;
        case UploadOutcome.failed:
          failed++;
        case UploadOutcome.uncertain:
          uncertain++;
        case UploadOutcome.skipped:
          break;
      }
      logs.add(
        SyncRecordLog(localId: items[i].localId, name: items[i].name, outcome: r.outcome.name, detail: r.message),
      );
      if (r.networkDown && i < items.length - 1) {
        aborted = true;
        break;
      }
    }
    onProgress?.call(SyncProgress(done: items.length, total: items.length));
    final run = SyncRun(
      id: _uuid.v4(),
      environmentId: local.environmentId,
      trigger: trigger,
      startedAt: started,
      finishedAt: _clock(),
      attempted: logs.length,
      uploaded: uploaded,
      failed: failed,
      alreadySynced: already,
      uncertain: uncertain,
      aborted: aborted,
      message: aborted ? 'Stopped: the server became unreachable.' : null,
      records: logs,
    );
    if (items.isNotEmpty) await history.add(run);
    return run;
  }

  /// Saves a new registration on the device and, when [upload] is true,
  /// uploads it immediately. The record is guarded as "in flight" from the
  /// moment it exists, so an automatic batch can't send it a second time.
  Future<RecordSyncResult> registerNew(
    EmployeeRegistration registration, {
    required bool upload,
    required SyncStatus offlineStatus,
    ProgressCallback? onSendProgress,
  }) async {
    final id = LocalEmployeeRepository.newLocalId();
    _inFlight.add(id);
    try {
      final record = await local.create(
        registration,
        status: upload ? SyncStatus.pendingSync : offlineStatus,
        localId: id,
      );
      if (!upload) return RecordSyncResult(UploadOutcome.skipped, record: record);
      return await _sync(id, onSendProgress: onSendProgress);
    } finally {
      _inFlight.remove(id);
    }
  }

  /// Uploads (or reconciles) one record. Safe to call at any time: it is a
  /// no-op for records already synced or already being uploaded.
  Future<RecordSyncResult> syncRecord(String localId) async {
    if (!_inFlight.add(localId)) return const RecordSyncResult(UploadOutcome.skipped, message: 'Already uploading');
    try {
      return await _sync(localId);
    } finally {
      _inFlight.remove(localId);
    }
  }

  Future<RecordSyncResult> _sync(String localId, {ProgressCallback? onSendProgress}) async {
    var e = local.get(localId);
    if (e == null) return const RecordSyncResult(UploadOutcome.skipped, message: 'Record not found');
    if (e.syncStatus == SyncStatus.synced) return RecordSyncResult(UploadOutcome.alreadySynced, record: e);
    if (e.isTestData) {
      final r = await local.update(
        localId,
        (x) => x.copyWith(
          syncStatus: SyncStatus.failed,
          permanentFailure: true,
          syncError: () => 'Test data is never uploaded.',
        ),
      );
      return RecordSyncResult(UploadOutcome.failed, record: r, message: 'Test data is never uploaded.');
    }

    // 1. Uncertain previous attempt: look for it on the server first.
    if (e.needsReconciliation) {
      try {
        final match = await findOnServer(e);
        if (match != null) {
          final linked = await _markSynced(localId, match, viaReconciliation: true);
          return RecordSyncResult(
            UploadOutcome.alreadySynced,
            record: linked,
            message: 'Found on server (id ${match.id})',
          );
        }
        e = await local.update(localId, (x) => x.copyWith(needsReconciliation: false));
      } on ApiException catch (err) {
        await local.update(localId, (x) => x.copyWith(lastSyncAttempt: () => _clock(), syncError: () => err.message));
        return RecordSyncResult(
          UploadOutcome.failed,
          record: local.get(localId),
          message: err.message,
          networkDown: err.isNetwork,
        );
      }
    }

    // 2. Rebuild the payload from the stored record and photo.
    final registration = await local.registrationFor(e!);
    if (registration == null) {
      final r = await local.update(
        localId,
        (x) => x.copyWith(
          syncStatus: SyncStatus.failed,
          permanentFailure: true,
          syncError: () => 'The photo for this employee is missing on this device.',
        ),
      );
      return RecordSyncResult(UploadOutcome.failed, record: r, message: 'Photo missing');
    }

    // 3. Persist SYNCING before sending (crash-safe state machine).
    await local.update(
      localId,
      (x) => x.copyWith(syncStatus: SyncStatus.syncing, lastSyncAttempt: () => _clock(), attempts: x.attempts + 1),
    );

    try {
      final result = await api.registerEmployee(registration, onSendProgress: onSendProgress);
      final emp = result.employee;
      final synced = await local.update(
        localId,
        (x) => x.copyWith(
          syncStatus: SyncStatus.synced,
          serverId: () => emp?.id,
          employeeNo: () => emp?.employeeNo,
          templateId: () => emp?.templateId,
          serverPhotoUrl: () => emp?.photoUrl,
          enrollmentSource: () => emp?.rawEnrollmentSource,
          liveWatchList: () => result.liveWatchList,
          serverWarning: () => result.recognitionDelayed ? result.warningMessage : null,
          lastSuccessfulSync: () => _clock(),
          syncError: () => null,
          nextRetryAt: () => null,
          permanentFailure: false,
          needsReconciliation: false,
        ),
      );
      if (emp != null) await cache.upsert(emp);
      return RecordSyncResult(UploadOutcome.uploaded, record: synced, result: result);
    } on ApiException catch (err) {
      return _fail(localId, err);
    } catch (_) {
      return _fail(
        localId,
        const ApiException.local(
          'Unexpected error during upload.',
          kind: ApiErrorKind.unknown,
          mayHaveReachedServer: true,
        ),
      );
    }
  }

  Future<RecordSyncResult> _fail(String localId, ApiException err) async {
    final now = _clock();
    if (err.mayHaveReachedServer) {
      final r = await local.update(
        localId,
        (x) => x.copyWith(
          syncStatus: SyncStatus.failed,
          needsReconciliation: true,
          nextRetryAt: () => now.add(retryDelay(x.attempts)),
          syncError: () =>
              'We could not confirm whether the server saved this employee '
              '(${err.message}). The server will be checked before retrying.',
        ),
      );
      return RecordSyncResult(UploadOutcome.uncertain, record: r, message: err.message, networkDown: err.isNetwork);
    }
    final rejected =
        err.statusCode >= 400 && err.statusCode < 500 && err.statusCode != 408 && err.statusCode != 429 ||
        err.kind == ApiErrorKind.validation;
    final r = await local.update(
      localId,
      (x) => x.copyWith(
        syncStatus: SyncStatus.failed,
        permanentFailure: rejected,
        nextRetryAt: () => rejected ? null : now.add(retryDelay(x.attempts)),
        syncError: () => err.message,
      ),
    );
    return RecordSyncResult(UploadOutcome.failed, record: r, message: err.message, networkDown: err.isNetwork);
  }

  Future<LocalEmployee?> _markSynced(String localId, Employee match, {bool viaReconciliation = false}) async {
    await cache.upsert(match);
    return local.update(
      localId,
      (x) => x.copyWith(
        syncStatus: SyncStatus.synced,
        serverId: () => match.id,
        employeeNo: () => match.employeeNo,
        templateId: () => match.templateId,
        serverPhotoUrl: () => match.photoUrl,
        enrollmentSource: () => match.rawEnrollmentSource,
        lastSuccessfulSync: () => _clock(),
        syncError: () => viaReconciliation ? null : x.syncError,
        nextRetryAt: () => null,
        needsReconciliation: false,
        permanentFailure: false,
      ),
    );
  }

  /// Searches the server for an employee matching [e] that no other local
  /// record is linked to. Throws [ApiException] when the server can't be
  /// queried (the record then stays in review).
  Future<Employee?> findOnServer(LocalEmployee e) async {
    final page = await api.getEmployees(EmployeeQuery(query: e.name, size: 100));
    final linked = {
      for (final x in local.all())
        if (x.serverId != null && x.localId != e.localId) x.serverId,
    };
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    final matches = page.content.where((s) {
      if (s.id != null && linked.contains(s.id)) return false;
      final dob = s.dateOfBirth;
      return norm(s.name) == norm(e.name) &&
          norm(s.designation) == norm(e.designation) &&
          dob != null &&
          dob.year == e.dateOfBirth.year &&
          dob.month == e.dateOfBirth.month &&
          dob.day == e.dateOfBirth.day;
    }).toList()..sort((a, b) => (b.enrolledAt ?? DateTime(0)).compareTo(a.enrolledAt ?? DateTime(0)));
    return matches.isEmpty ? null : matches.first;
  }
}
