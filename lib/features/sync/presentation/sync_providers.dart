import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/app_notifier.dart';
import '../../../core/services/providers.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../data/models/activity.dart';
import '../../connectivity/connectivity_service.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../environments/presentation/providers/environment_providers.dart';
import '../data/sync_engine.dart';
import '../data/sync_history.dart';

final syncHistoryRepositoryProvider = Provider<SyncHistoryRepository>((ref) => SyncHistoryRepository(
      ref.watch(localDatabaseProvider).box(BoxNames.syncHistory),
      environmentId: ref.watch(activeEnvironmentProvider).environmentId,
    ));

/// One engine per environment. Interrupted uploads from a previous session
/// are recovered (marked for review) when it is created.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    local: ref.watch(localEmployeeRepositoryProvider),
    api: ref.watch(employeeApiServiceProvider),
    history: ref.watch(syncHistoryRepositoryProvider),
    cache: ref.watch(serverEmployeeCacheProvider),
  );
  unawaited(engine.recoverInterrupted());
  return engine;
});

class SyncHistoryNotifier extends Notifier<List<SyncRun>> {
  @override
  List<SyncRun> build() {
    final repo = ref.watch(syncHistoryRepositoryProvider);
    final sub = repo.changes.listen((_) => state = repo.all());
    ref.onDispose(sub.cancel);
    return repo.all();
  }
}

final syncHistoryProvider = NotifierProvider<SyncHistoryNotifier, List<SyncRun>>(SyncHistoryNotifier.new);

/// Global notifier (overridable in tests).
final appNotifierProvider = Provider<AppNotifier>((ref) => AppNotifier());

@immutable
class SyncState {
  const SyncState({this.running = false, this.progress, this.lastRun});
  final bool running;
  final SyncProgress? progress;
  final SyncRun? lastRun;
}

/// Why a requested sync didn't start.
enum SyncStart { started, offline, nothingToSync, alreadyRunning }

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() {
    ref.watch(activeEnvironmentProvider);
    return const SyncState();
  }

  SyncEngine get _engine => ref.read(syncEngineProvider);

  int pendingCount(SyncSelection s) => _engine.candidates(s).length;

  /// Checks the server first: never starts a doomed upload while offline.
  Future<bool> _serverReachable() async {
    final status = ref.read(connectionStatusProvider);
    if (status.isOnline) return true;
    if (!status.device.hasNetwork) return false;
    await ref.read(connectionStatusProvider.notifier).check();
    return ref.read(connectionStatusProvider).isOnline;
  }

  /// Runs a batch. Returns how it went so the UI can react (e.g. show the
  /// offline dialog).
  Future<(SyncStart, SyncRun?)> sync({
    SyncSelection selection = SyncSelection.manual,
    SyncTrigger trigger = SyncTrigger.manual,
    bool notify = true,
  }) async {
    if (_engine.isRunning) return (SyncStart.alreadyRunning, null);
    if (_engine.candidates(selection).isEmpty) return (SyncStart.nothingToSync, null);
    if (!await _serverReachable()) return (SyncStart.offline, null);
    state = SyncState(running: true, lastRun: state.lastRun, progress: const SyncProgress(done: 0, total: 0));
    try {
      final run = await _engine.run(selection, trigger: trigger, onProgress: (p) {
        state = SyncState(running: true, progress: p, lastRun: state.lastRun);
      });
      state = SyncState(lastRun: run);
      ref.read(employeeRefresherProvider)();
      await _log(run);
      if (notify) _notify(run);
      return (SyncStart.started, run);
    } catch (_) {
      state = SyncState(lastRun: state.lastRun);
      rethrow;
    }
  }

  Future<(SyncStart, SyncRun?)> retryFailed() =>
      sync(selection: SyncSelection.failedOnly, trigger: SyncTrigger.retryFailed);

  /// Uploads (or reconciles) a single employee.
  Future<(SyncStart, RecordSyncResult?)> syncOne(String localId) async {
    if (!await _serverReachable()) return (SyncStart.offline, null);
    final r = await _engine.syncRecord(localId);
    ref.read(employeeRefresherProvider)();
    return (SyncStart.started, r);
  }

  Future<void> _log(SyncRun run) async {
    if (run.attempted == 0) return;
    final env = ref.read(activeEnvironmentProvider);
    await ref.read(activityRepositoryProvider).log(
          run.success ? ActivityType.employeeRegistered : ActivityType.registrationFailed,
          'Sync: ${run.uploaded} uploaded, ${run.failed + run.uncertain} failed',
          subtitle: '${run.trigger.label} · ${env.environmentName}',
          environmentId: env.environmentId,
        );
  }

  void _notify(SyncRun run) {
    final n = ref.read(appNotifierProvider);
    if (run.attempted == 0) return;
    final failed = run.failed + run.uncertain;
    if (failed == 0 && !run.aborted) {
      n.show(
        run.uploaded + run.alreadySynced == 1 ? 'The pending employee has been synchronized.' : 'All pending employees have been synchronized.',
        type: SnackType.success,
      );
    } else if (run.aborted) {
      n.show('Synchronization paused: the server became unreachable. Your records are safe on this device.',
          type: SnackType.warning);
    } else {
      n.show(
        'Synchronization completed with $failed failed record${failed == 1 ? '' : 's'}. You can retry them.',
        type: SnackType.warning,
        actionLabel: 'Retry',
        onAction: () => retryFailed(),
      );
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Reacts to connectivity changes: notifies the user once per transition,
/// and starts automatic synchronization when the server becomes reachable
/// (or a failed record's retry time has come), respecting the automatic
/// sync and Wi-Fi-only settings. Kept alive by the app shell.
final syncCoordinatorProvider = Provider<void>((ref) {
  void maybeAutoSync({required bool announce}) {
    final controller = ref.read(syncControllerProvider.notifier);
    final waiting = controller.pendingCount(SyncSelection.manual);
    final due = controller.pendingCount(SyncSelection.automatic);
    final settings = ref.read(settingsProvider);
    final device = ref.read(connectionStatusProvider).device;
    final notifier = ref.read(appNotifierProvider);
    final autoAllowed = settings.autoSync && (!settings.syncOnWifiOnly || device.isUnmetered);
    if (autoAllowed && due > 0) {
      if (announce) {
        notifier.show('Connection restored. Synchronizing $due employee${due == 1 ? '' : 's'}…');
      }
      unawaited(controller.sync(selection: SyncSelection.automatic, trigger: SyncTrigger.automatic));
    } else if (announce && waiting > 0) {
      notifier.show(
        'Connection restored. You have $waiting employee${waiting == 1 ? '' : 's'} waiting to synchronize.',
        actionLabel: 'Sync now',
        onAction: () => controller.sync(),
      );
    }
  }

  ref.listen<ConnectionStatus>(connectionStatusProvider, (prev, next) {
    final before = prev?.status;
    final now = next.status;
    final notifier = ref.read(appNotifierProvider);
    if (before != now) {
      if (now == NetworkStatus.online && (before == NetworkStatus.offline || before == NetworkStatus.serverUnavailable)) {
        maybeAutoSync(announce: true);
        return;
      }
      if (now == NetworkStatus.online && before == NetworkStatus.checking) {
        maybeAutoSync(announce: false); // first check at startup
        return;
      }
      if (now == NetworkStatus.offline && before == NetworkStatus.online) {
        notifier.show('You are offline. You can continue registering employees.', type: SnackType.warning);
      } else if (now == NetworkStatus.serverUnavailable && before == NetworkStatus.online) {
        notifier.show('Unable to connect to the server. Your locally saved records are safe.', type: SnackType.warning);
      }
    } else if (now == NetworkStatus.online && prev?.lastSuccessAt != next.lastSuccessAt) {
      // Periodic check succeeded: pick up records whose retry time has come.
      if (!ref.read(syncControllerProvider).running) maybeAutoSync(announce: false);
    }
  });
});

/// Last time any record reached the server (this environment).
final lastSuccessfulSyncProvider = Provider<DateTime?>((ref) {
  DateTime? best;
  for (final e in ref.watch(localEmployeesProvider)) {
    final t = e.lastSuccessfulSync;
    if (t != null && (best == null || t.isAfter(best))) best = t;
  }
  return best;
});

final lastSyncAttemptProvider = Provider<DateTime?>((ref) {
  final runs = ref.watch(syncHistoryProvider);
  DateTime? best = runs.isEmpty ? null : runs.first.startedAt;
  for (final e in ref.watch(localEmployeesProvider)) {
    final t = e.lastSyncAttempt;
    if (t != null && (best == null || t.isAfter(best))) best = t;
  }
  return best;
});

/// Records that will be picked up by "Sync now".
final syncableCountProvider = Provider<int>((ref) {
  ref.watch(localEmployeesProvider);
  return ref.read(syncEngineProvider).candidates(SyncSelection.manual).length;
});
