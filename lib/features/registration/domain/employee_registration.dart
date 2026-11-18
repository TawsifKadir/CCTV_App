import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../employees/data/models/employee.dart';
import 'employee_photo.dart';

/// The four fields of the backend's `EmployeeForm`.
@immutable
class EmployeeRegistration {
  const EmployeeRegistration({
    required this.name,
    required this.dateOfBirth,
    required this.designation,
    required this.photo,
  });

  final String name;
  final DateTime dateOfBirth;
  final String designation;
  final EmployeePhoto photo;

  /// Multipart field names. These must match `EmployeeForm` exactly.
  static const fieldName = 'name';
  static const fieldDateOfBirth = 'dateOfBirth';
  static const fieldDesignation = 'designation';
  static const fieldPhoto = 'photo';

  /// Validation errors keyed by field name (empty when valid).
  Map<String, String> validate({DateTime? now}) {
    final errors = <String, String>{};
    final n = EmployeeValidators.name(name);
    if (n != null) errors[fieldName] = n;
    final d = EmployeeValidators.dateOfBirth(dateOfBirth, now: now);
    if (d != null) errors[fieldDateOfBirth] = d;
    final g = EmployeeValidators.designation(designation);
    if (g != null) errors[fieldDesignation] = g;
    final p = PhotoValidator.validate(photo.bytes);
    if (p != null) errors[fieldPhoto] = p;
    return errors;
  }

  /// `multipart/form-data` body for `POST /api/employee/add`.
  FormData toFormData() => FormData.fromMap({
    fieldName: name.trim(),
    fieldDateOfBirth: isoDate(dateOfBirth),
    fieldDesignation: designation.trim(),
    fieldPhoto: MultipartFile.fromBytes(
      photo.bytes,
      filename: photo.filename,
      contentType: DioMediaType.parse(photo.format.mimeType),
    ),
  });
}

/// Client-side checks for the registration form. The backend remains the
/// authority and its error messages are shown verbatim.
class EmployeeValidators {
  EmployeeValidators._();

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Name looks too short';
    if (v.length > 120) return 'Name must be under 120 characters';
    return null;
  }

  static String? designation(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Designation is required';
    if (v.length > 120) return 'Designation must be under 120 characters';
    return null;
  }

  static String? dateOfBirth(DateTime? value, {DateTime? now}) {
    if (value == null) return 'Date of birth is required';
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    if (DateTime(value.year, value.month, value.day).isAfter(day)) return 'Date of birth cannot be in the future';
    if (value.year < today.year - 120) return 'Please check the date of birth';
    return null;
  }
}
