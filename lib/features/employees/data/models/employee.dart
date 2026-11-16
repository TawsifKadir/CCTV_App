import 'package:flutter/foundation.dart';

/// How an employee's photograph was enrolled (`enrollmentSource`).
enum EnrollmentSource {
  photo('photo', 'Photo upload'),
  capture('capture', 'Camera capture');

  const EnrollmentSource(this.apiValue, this.label);

  /// Value used by the backend (`source` query parameter).
  final String apiValue;
  final String label;

  static EnrollmentSource? fromApi(Object? value) {
    if (value is! String) return null;
    final v = value.trim().toLowerCase();
    for (final s in values) {
      if (s.apiValue == v) return s;
    }
    return null;
  }
}

/// An employee record as returned by `GET /api/employee/list`.
///
/// Parsing is tolerant: every field except the name may be missing or null,
/// numbers may arrive as strings, and unknown fields are ignored.
@immutable
class Employee {
  const Employee({
    this.id,
    this.employeeNo,
    required this.name,
    this.dateOfBirth,
    this.designation,
    this.templateId,
    this.templateBytes,
    this.enrolledAt,
    this.photoUrl,
    this.enrollmentSource,
    this.rawEnrollmentSource,
  });

  final int? id;
  final int? employeeNo;
  final String name;
  final DateTime? dateOfBirth;
  final String? designation;
  final String? templateId;
  final int? templateBytes;
  final DateTime? enrolledAt;

  /// Server-relative photo path, e.g. `/api/employee/1/photo`. Resolve it
  /// with the active environment before loading.
  final String? photoUrl;
  final EnrollmentSource? enrollmentSource;

  /// Original `enrollmentSource` text, kept for values the app doesn't know.
  final String? rawEnrollmentSource;

  bool get hasPhoto => photoUrl != null && photoUrl!.trim().isNotEmpty;

  /// Stable key for lists and routing.
  String get key => id?.toString() ?? templateId ?? 'n:$name';

  String get sourceLabel => enrollmentSource?.label ?? rawEnrollmentSource ?? '—';

  factory Employee.fromJson(Map<String, dynamic> j) {
    final source = j['enrollmentSource'] ?? j['source'];
    return Employee(
      id: parseInt(j['id']),
      employeeNo: parseInt(j['employeeNo']),
      name: parseString(j['name']) ?? parseString(j['fullName']) ?? 'Unnamed employee',
      dateOfBirth: parseDate(j['dateOfBirth']),
      designation: parseString(j['designation']),
      templateId: parseString(j['templateId']),
      templateBytes: parseInt(j['templateBytes']),
      enrolledAt: parseDate(j['enrolledAt']),
      photoUrl: parseString(j['photoUrl']),
      enrollmentSource: EnrollmentSource.fromApi(source),
      rawEnrollmentSource: parseString(source),
    );
  }

  /// `true` when [j] looks like an employee document (used to tolerate
  /// registration responses whose schema is not fixed).
  static bool looksLikeEmployee(Map<String, dynamic> j) =>
      j.containsKey('id') || j.containsKey('employeeNo') || j.containsKey('name') || j.containsKey('fullName');

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeNo': employeeNo,
        'name': name,
        'dateOfBirth': dateOfBirth == null ? null : isoDate(dateOfBirth!),
        'designation': designation,
        'templateId': templateId,
        'templateBytes': templateBytes,
        'enrolledAt': enrolledAt?.toIso8601String(),
        'photoUrl': photoUrl,
        'enrollmentSource': rawEnrollmentSource ?? enrollmentSource?.apiValue,
      };

  @override
  bool operator ==(Object other) => other is Employee && other.key == key && other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(key, photoUrl);
}

// ---------------------------------------------------------------------------
// Tolerant JSON helpers
// ---------------------------------------------------------------------------

int? parseInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

bool? parseBool(Object? v) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  return null;
}

String? parseString(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Parses ISO dates and date-times (`1998-05-20`, `2026-11-16T10:30:00`).
/// Values without a zone are treated as local time.
DateTime? parseDate(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  return DateTime.tryParse(v.trim());
}

/// Formats a date as the backend's `LocalDate.parse` expects: `YYYY-MM-DD`.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
