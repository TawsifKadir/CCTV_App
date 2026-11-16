import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/constants/app_constants.dart';

enum SyncTrigger {
  automatic('Automatic'),
  manual('Sync now'),
  retryFailed('Retry failed'),
  single('Single employee');

  const SyncTrigger(this.label);
  final String label;
}

/// Per-record outcome inside a run (shown in admin diagnostics).
@immutable
class SyncRecordLog {
  const SyncRecordLog({required this.localId, required this.name, required this.outcome, this.detail});
  final String localId;
  final String name;
  final String outcome; // uploaded | failed | alreadySynced | uncertain | skipped
  final String? detail;

  Map<String, dynamic> toJson() => {'localId': localId, 'name': name, 'outcome': outcome, 'detail': detail};
  factory SyncRecordLog.fromJson(Map<String, dynamic> j) => SyncRecordLog(
        localId: j['localId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        outcome: j['outcome'] as String? ?? '',
        detail: j['detail'] as String?,
      );
}

/// Summary of one synchronization run.
@immutable
class SyncRun {
  const SyncRun({
    required this.id,
    required this.environmentId,
    required this.trigger,
    required this.startedAt,
    required this.finishedAt,
    required this.attempted,
    required this.uploaded,
    required this.failed,
    required this.alreadySynced,
    this.uncertain = 0,
    this.aborted = false,
    this.message,
    this.records = const [],
  });

  final String id;
  final String environmentId;
  final SyncTrigger trigger;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int attempted;
  final int uploaded;
  final int failed;

  /// Found already on the server (e.g. by reconciliation) — not re-uploaded.
  final int alreadySynced;

  /// Outcome unknown; will be checked against the server before retrying.
  final int uncertain;

  /// Stopped early because the server became unreachable.
  final bool aborted;
  final String? message;
  final List<SyncRecordLog> records;

  Duration get duration => finishedAt.difference(startedAt);
  bool get success => failed == 0 && uncertain == 0 && !aborted;

  String get resultLabel {
    if (attempted == 0) return 'Nothing to sync';
    if (success) return 'Completed';
    if (uploaded + alreadySynced == 0) return 'Failed';
    return 'Partially completed';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'environmentId': environmentId,
        'trigger': trigger.name,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'attempted': attempted,
        'uploaded': uploaded,
        'failed': failed,
        'alreadySynced': alreadySynced,
        'uncertain': uncertain,
        'aborted': aborted,
        'message': message,
        'records': [for (final r in records) r.toJson()],
      };

  factory SyncRun.fromJson(Map<String, dynamic> j) => SyncRun(
        id: j['id'] as String,
        environmentId: j['environmentId'] as String? ?? '',
        trigger: SyncTrigger.values.firstWhere((t) => t.name == j['trigger'], orElse: () => SyncTrigger.manual),
        startedAt: DateTime.parse(j['startedAt'] as String),
        finishedAt: DateTime.parse(j['finishedAt'] as String),
        attempted: j['attempted'] as int? ?? 0,
        uploaded: j['uploaded'] as int? ?? 0,
        failed: j['failed'] as int? ?? 0,
        alreadySynced: j['alreadySynced'] as int? ?? 0,
        uncertain: j['uncertain'] as int? ?? 0,
        aborted: j['aborted'] as bool? ?? false,
        message: j['message'] as String?,
        records: [
          for (final r in (j['records'] as List? ?? const []))
            if (r is Map) SyncRecordLog.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
}

class SyncHistoryRepository {
  SyncHistoryRepository(this._box, {required this.environmentId});
  final Box<dynamic> _box;
  final String environmentId;

  Stream<void> get changes => _box.watch().map((_) {});

  List<SyncRun> all() {
    final out = <SyncRun>[];
    for (final raw in _box.values) {
      if (raw is! String) continue;
      try {
        final r = SyncRun.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        if (r.environmentId == environmentId) out.add(r);
      } catch (_) {}
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }

  Future<void> add(SyncRun run) async {
    await _box.put(run.id, jsonEncode(run.toJson()));
    final runs = all();
    if (runs.length > AppConstants.maxSyncHistory) {
      await _box.deleteAll(runs.skip(AppConstants.maxSyncHistory).map((r) => r.id));
    }
  }

  DateTime? get lastSuccessfulRun {
    for (final r in all()) {
      if (r.uploaded + r.alreadySynced > 0) return r.finishedAt;
    }
    return null;
  }

  Future<void> clear() async => _box.deleteAll(all().map((r) => r.id));
}
