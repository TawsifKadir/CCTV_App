import 'package:flutter/foundation.dart';

import 'employee.dart';
import 'local_employee.dart';

/// One row in the unified employee list: a server record, a local record,
/// or both (a server record this device registered).
@immutable
class EmployeeRecord {
  const EmployeeRecord({this.server, this.local}) : assert(server != null || local != null);

  final Employee? server;
  final LocalEmployee? local;

  /// Display fields: server values win once the record is on the server.
  Employee get view => server ?? local!.toEmployee();

  /// Stable key: `l:<localId>` for device-only records, the server id otherwise.
  String get key => server != null ? server!.key : 'l:${local!.localId}';

  SyncStatus get status => server != null ? SyncStatus.synced : local!.syncStatus;
  bool get isOnServer => status == SyncStatus.synced;
  bool get registeredOnThisDevice => local != null;

  String get statusLabel => server != null ? SyncStatus.synced.label : local!.statusLabel;

  String get name => view.name;

  /// Local photo available on this device (works offline).
  String? get localPhotoRef => local?.localPhotoReference;
}

/// Sync-state filter for the employee list.
enum RecordFilter {
  all('All employees'),
  onServer('On server'),
  localOnly('Local only'),
  pending('Pending sync'),
  failed('Failed sync');

  const RecordFilter(this.label);
  final String label;

  /// Filters answered entirely from the device (no server request).
  bool get isLocal => this == localOnly || this == pending || this == failed;

  bool matches(SyncStatus s) => switch (this) {
    RecordFilter.all => true,
    RecordFilter.onServer => s == SyncStatus.synced,
    RecordFilter.localOnly => s == SyncStatus.localOnly,
    RecordFilter.pending => s == SyncStatus.pendingSync || s == SyncStatus.syncing,
    RecordFilter.failed => s == SyncStatus.failed,
  };
}
