import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/environment_config.dart';
import '../../../../core/services/providers.dart';
import '../../../../data/models/activity.dart';
import '../../../connectivity/connectivity_service.dart';
import '../../../employees/data/models/local_employee.dart';
import '../../../employees/data/models/registration_result.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../../environments/presentation/providers/environment_providers.dart';
import '../../../sync/data/sync_engine.dart';
import '../../../sync/presentation/sync_providers.dart';
import '../../domain/employee_photo.dart';
import '../../domain/employee_registration.dart';

/// What the success screen needs after a registration.
@immutable
class RegistrationOutcome {
  const RegistrationOutcome({
    required this.environment,
    required this.submittedName,
    required this.designation,
    required this.photo,
    this.result,
    this.record,
    this.uncertain = false,
  });

  /// Server response; `null` when the employee was saved on the device only.
  final RegistrationResult? result;

  /// The device record (always present for registrations made through the
  /// offline-first flow).
  final LocalEmployee? record;

  /// The upload's outcome is unknown; the server will be checked before any
  /// retry.
  final bool uncertain;

  final EnvironmentConfig environment;
  final String submittedName;
  final String designation;
  final EmployeePhoto photo;

  bool get savedOnServer => result != null;
  bool get savedOnDeviceOnly => result == null;
}

@immutable
class RegistrationState {
  const RegistrationState({this.submitting = false, this.progress, this.error});

  final bool submitting;

  /// Upload progress 0–1, when known.
  final double? progress;

  /// The server rejected the data (shown on the form). Network problems are
  /// never errors here: the employee is saved on the device instead.
  final String? error;

  static const idle = RegistrationState();
}

/// Offline-first registration:
/// * Server reachable → the record is saved on the device, uploaded at
///   once, and marked SYNCED with the server's id.
/// * Offline / server unavailable, or the upload fails for network reasons →
///   the record and photo stay safely on the device (PENDING_SYNC, or
///   LOCAL_ONLY when automatic sync is off) and are uploaded later.
/// * The server rejects the data (4xx, e.g. invalid date or no usable photo)
///   → nothing is kept and the backend's message is shown on the form.
class RegistrationController extends AutoDisposeNotifier<RegistrationState> {
  @override
  RegistrationState build() => RegistrationState.idle;

  void clearError() {
    if (state.error != null) state = RegistrationState(submitting: state.submitting, progress: state.progress);
  }

  /// Returns `null` on rejection (see [state.error]) or when a submission is
  /// already running (duplicate taps are ignored).
  Future<RegistrationOutcome?> submit(EmployeeRegistration registration) async {
    if (state.submitting) return null;
    final env = ref.read(activeEnvironmentProvider);
    final engine = ref.read(syncEngineProvider);
    final local = ref.read(localEmployeeRepositoryProvider);
    final activity = ref.read(activityRepositoryProvider);
    final autoSync = ref.read(settingsProvider).autoSync;
    final upload = ref.read(connectionStatusProvider).shouldAttemptServer;
    state = const RegistrationState(submitting: true, progress: 0);

    RegistrationOutcome outcome({RegistrationResult? result, LocalEmployee? record, bool uncertain = false}) => RegistrationOutcome(
          result: result,
          record: record,
          uncertain: uncertain,
          environment: env,
          submittedName: registration.name.trim(),
          designation: registration.designation.trim(),
          photo: registration.photo,
        );

    try {
      final r = await engine.registerNew(
        registration,
        upload: upload,
        offlineStatus: autoSync ? SyncStatus.pendingSync : SyncStatus.localOnly,
        onSendProgress: (sent, total) {
          if (total > 0) state = RegistrationState(submitting: true, progress: sent / total);
        },
      );
      final record = r.record;
      final name = registration.name.trim();
      final where = '${registration.designation.trim()} · ${env.environmentName}';

      if (r.outcome == UploadOutcome.uploaded) {
        ref.read(employeeRefresherProvider)();
        final delayed = r.result?.recognitionDelayed ?? false;
        await activity.log(
          delayed ? ActivityType.recognitionPending : ActivityType.employeeRegistered,
          delayed ? '$name registered · recognition pending' : '$name registered',
          subtitle: where,
          environmentId: env.environmentId,
        );
        state = RegistrationState.idle;
        return outcome(result: r.result, record: record);
      }

      if (r.outcome == UploadOutcome.failed && (record?.permanentFailure ?? false)) {
        // Rejected by the server: don't keep data the server will never accept.
        if (record != null) await local.delete(record.localId);
        state = RegistrationState(error: r.message ?? 'The server rejected this registration.');
        return null;
      }

      // Offline, server unavailable, transient failure or uncertain outcome:
      // the registration is safe on the device.
      await activity.log(
        ActivityType.recognitionPending,
        '$name saved on this device',
        subtitle: '$where · waiting to synchronize',
        environmentId: env.environmentId,
      );
      state = RegistrationState.idle;
      return outcome(record: record, uncertain: r.outcome == UploadOutcome.uncertain);
    } catch (_) {
      state = const RegistrationState(error: 'Something went wrong while saving. Please try again.');
      return null;
    }
  }
}

final registrationControllerProvider =
    AutoDisposeNotifierProvider<RegistrationController, RegistrationState>(RegistrationController.new);
