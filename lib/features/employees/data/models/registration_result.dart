import 'package:flutter/foundation.dart';

import 'employee.dart';

/// Response of `POST /api/employee/add` (HTTP 201).
///
/// The backend returns `view(employee)` plus `liveWatchList` and an optional
/// `warning`. Only those two keys are relied upon; the employee fields are
/// parsed when present.
@immutable
class RegistrationResult {
  const RegistrationResult({
    required this.statusCode,
    this.employee,
    this.liveWatchList,
    this.warning,
    this.raw = const {},
  });

  final int statusCode;
  final Employee? employee;

  /// `false` when the employee was saved but is not yet in the live
  /// recognition watch list. The registration itself still succeeded.
  final bool? liveWatchList;
  final String? warning;
  final Map<String, dynamic> raw;

  bool get recognitionDelayed => liveWatchList == false || (warning != null && warning!.isNotEmpty);

  /// Message to show when [recognitionDelayed].
  String get warningMessage =>
      (warning != null && warning!.isNotEmpty)
          ? warning!
          : 'The employee was saved, but live recognition is not available for them yet.';

  factory RegistrationResult.fromJson(int statusCode, Object? json) {
    if (json is! Map) return RegistrationResult(statusCode: statusCode);
    final j = Map<String, dynamic>.from(json);
    // Some APIs wrap the record: accept {"employee": {...}} as well.
    final nested = j['employee'];
    final employeeJson = nested is Map ? Map<String, dynamic>.from(nested) : j;
    return RegistrationResult(
      statusCode: statusCode,
      employee: Employee.looksLikeEmployee(employeeJson) ? Employee.fromJson(employeeJson) : null,
      liveWatchList: parseBool(j['liveWatchList']),
      warning: parseString(j['warning']),
      raw: j,
    );
  }
}
