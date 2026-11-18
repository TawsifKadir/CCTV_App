import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../registration/domain/employee_photo.dart';
import 'employee.dart';

/// Where an employee record stands relative to the backend.
enum SyncStatus {
  /// On this device only, never uploaded (automatic sync was off).
  localOnly('LOCAL_ONLY', 'Local only', Icons.smartphone_rounded, AppColors.warning),

  /// Waiting to be uploaded.
  pendingSync('PENDING_SYNC', 'Sync pending', Icons.cloud_upload_outlined, AppColors.info),

  /// An upload is in progress.
  syncing('SYNCING', 'Syncing', Icons.sync_rounded, AppColors.info),

  /// Registered on the backend.
  synced('SYNCED', 'On server', Icons.cloud_done_outlined, AppColors.success),

  /// The last attempt failed; the record is still safe on this device.
  failed('FAILED', 'Sync failed', Icons.error_outline_rounded, AppColors.error);

  const SyncStatus(this.code, this.label, this.icon, this.color);
  final String code;
  final String label;
  final IconData icon;
  final Color color;

  bool get isOnServer => this == synced;

  static SyncStatus fromCode(String? c) =>
      SyncStatus.values.firstWhere((s) => s.code == c || s.name == c, orElse: () => SyncStatus.pendingSync);
}

/// An employee registered on this device (persisted, with its photo).
///
/// `localId` is a stable UUID created on the device; it is never confused
/// with the server's `serverId`, which is filled in once the backend
/// accepts the registration.
@immutable
class LocalEmployee {
  const LocalEmployee({
    required this.localId,
    required this.name,
    required this.dateOfBirth,
    required this.designation,
    required this.localPhotoReference,
    required this.photoFormat,
    required this.photoOrigin,
    required this.photoBytes,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    required this.backendEnvironmentId,
    this.serverId,
    this.employeeNo,
    this.serverPhotoUrl,
    this.enrollmentSource,
    this.templateId,
    this.liveWatchList,
    this.serverWarning,
    this.lastSyncAttempt,
    this.lastSuccessfulSync,
    this.syncError,
    this.attempts = 0,
    this.nextRetryAt,
    this.permanentFailure = false,
    this.needsReconciliation = false,
    this.isTestData = false,
  });

  final String localId;
  final int? serverId;
  final int? employeeNo;
  final String name;
  final DateTime dateOfBirth;
  final String designation;

  /// Key of the photo in the device's photo store.
  final String localPhotoReference;
  final PhotoFormat photoFormat;
  final PhotoOrigin photoOrigin;
  final int photoBytes;
  final String? serverPhotoUrl;

  /// As reported by the backend once synced.
  final String? enrollmentSource;
  final String? templateId;
  final bool? liveWatchList;
  final String? serverWarning;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final DateTime? lastSyncAttempt;
  final DateTime? lastSuccessfulSync;
  final String? syncError;
  final String backendEnvironmentId;

  /// Upload attempts so far (drives the automatic retry backoff).
  final int attempts;

  /// Earliest time an *automatic* retry may run.
  final DateTime? nextRetryAt;

  /// The server rejected the data (4xx): retrying unchanged won't help, so
  /// automatic sync skips it. Manual "Retry failed" still tries.
  final bool permanentFailure;

  /// The outcome of the last upload is unknown — the server may have saved
  /// it. Before any retry the app searches the server for a matching
  /// employee, so a retry can't silently create a duplicate.
  final bool needsReconciliation;

  /// Created by the admin test-data tool. Never uploaded.
  final bool isTestData;

  bool get isUnsynced => syncStatus != SyncStatus.synced;

  /// Label shown in the UI (accounts for the "needs review" sub-state).
  String get statusLabel => needsReconciliation && syncStatus == SyncStatus.failed ? 'Needs review' : syncStatus.label;

  /// Display model shared with server records.
  Employee toEmployee() => Employee(
    id: serverId,
    employeeNo: employeeNo,
    name: name,
    dateOfBirth: dateOfBirth,
    designation: designation,
    templateId: templateId,
    enrolledAt: createdAt,
    photoUrl: serverPhotoUrl,
    enrollmentSource: EnrollmentSource.fromApi(enrollmentSource),
    rawEnrollmentSource: enrollmentSource,
  );

  LocalEmployee copyWith({
    int? Function()? serverId,
    int? Function()? employeeNo,
    String? Function()? serverPhotoUrl,
    String? Function()? enrollmentSource,
    String? Function()? templateId,
    bool? Function()? liveWatchList,
    String? Function()? serverWarning,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    DateTime? Function()? lastSyncAttempt,
    DateTime? Function()? lastSuccessfulSync,
    String? Function()? syncError,
    int? attempts,
    DateTime? Function()? nextRetryAt,
    bool? permanentFailure,
    bool? needsReconciliation,
  }) => LocalEmployee(
    localId: localId,
    name: name,
    dateOfBirth: dateOfBirth,
    designation: designation,
    localPhotoReference: localPhotoReference,
    photoFormat: photoFormat,
    photoOrigin: photoOrigin,
    photoBytes: photoBytes,
    createdAt: createdAt,
    backendEnvironmentId: backendEnvironmentId,
    isTestData: isTestData,
    serverId: serverId == null ? this.serverId : serverId(),
    employeeNo: employeeNo == null ? this.employeeNo : employeeNo(),
    serverPhotoUrl: serverPhotoUrl == null ? this.serverPhotoUrl : serverPhotoUrl(),
    enrollmentSource: enrollmentSource == null ? this.enrollmentSource : enrollmentSource(),
    templateId: templateId == null ? this.templateId : templateId(),
    liveWatchList: liveWatchList == null ? this.liveWatchList : liveWatchList(),
    serverWarning: serverWarning == null ? this.serverWarning : serverWarning(),
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    lastSyncAttempt: lastSyncAttempt == null ? this.lastSyncAttempt : lastSyncAttempt(),
    lastSuccessfulSync: lastSuccessfulSync == null ? this.lastSuccessfulSync : lastSuccessfulSync(),
    syncError: syncError == null ? this.syncError : syncError(),
    attempts: attempts ?? this.attempts,
    nextRetryAt: nextRetryAt == null ? this.nextRetryAt : nextRetryAt(),
    permanentFailure: permanentFailure ?? this.permanentFailure,
    needsReconciliation: needsReconciliation ?? this.needsReconciliation,
  );

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'serverId': serverId,
    'employeeNo': employeeNo,
    'name': name,
    'dateOfBirth': isoDate(dateOfBirth),
    'designation': designation,
    'localPhotoReference': localPhotoReference,
    'photoFormat': photoFormat.name,
    'photoOrigin': photoOrigin.name,
    'photoBytes': photoBytes,
    'serverPhotoUrl': serverPhotoUrl,
    'enrollmentSource': enrollmentSource,
    'templateId': templateId,
    'liveWatchList': liveWatchList,
    'serverWarning': serverWarning,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus.code,
    'lastSyncAttempt': lastSyncAttempt?.toIso8601String(),
    'lastSuccessfulSync': lastSuccessfulSync?.toIso8601String(),
    'syncError': syncError,
    'backendEnvironmentId': backendEnvironmentId,
    'attempts': attempts,
    'nextRetryAt': nextRetryAt?.toIso8601String(),
    'permanentFailure': permanentFailure,
    'needsReconciliation': needsReconciliation,
    'isTestData': isTestData,
  };

  factory LocalEmployee.fromJson(Map<String, dynamic> j) => LocalEmployee(
    localId: j['localId'] as String,
    serverId: parseInt(j['serverId']),
    employeeNo: parseInt(j['employeeNo']),
    name: j['name'] as String? ?? '',
    dateOfBirth: parseDate(j['dateOfBirth']) ?? DateTime(1900),
    designation: j['designation'] as String? ?? '',
    localPhotoReference: j['localPhotoReference'] as String? ?? '',
    photoFormat: PhotoFormat.values.firstWhere((f) => f.name == j['photoFormat'], orElse: () => PhotoFormat.jpeg),
    photoOrigin: PhotoOrigin.values.firstWhere((o) => o.name == j['photoOrigin'], orElse: () => PhotoOrigin.upload),
    photoBytes: parseInt(j['photoBytes']) ?? 0,
    serverPhotoUrl: parseString(j['serverPhotoUrl']),
    enrollmentSource: parseString(j['enrollmentSource']),
    templateId: parseString(j['templateId']),
    liveWatchList: parseBool(j['liveWatchList']),
    serverWarning: parseString(j['serverWarning']),
    createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
    updatedAt: parseDate(j['updatedAt']) ?? DateTime.now(),
    syncStatus: SyncStatus.fromCode(j['syncStatus'] as String?),
    lastSyncAttempt: parseDate(j['lastSyncAttempt']),
    lastSuccessfulSync: parseDate(j['lastSuccessfulSync']),
    syncError: parseString(j['syncError']),
    backendEnvironmentId: j['backendEnvironmentId'] as String? ?? '',
    attempts: parseInt(j['attempts']) ?? 0,
    nextRetryAt: parseDate(j['nextRetryAt']),
    permanentFailure: j['permanentFailure'] as bool? ?? false,
    needsReconciliation: j['needsReconciliation'] as bool? ?? false,
    isTestData: j['isTestData'] as bool? ?? false,
  );
}
