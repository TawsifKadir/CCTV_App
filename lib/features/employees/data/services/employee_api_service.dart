import 'package:dio/dio.dart';

import '../../../../core/config/api_endpoints.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../registration/domain/employee_registration.dart';
import '../models/employee_page.dart';
import '../models/employee_query.dart';
import '../models/registration_result.dart';

/// HTTP calls to the Spring Boot employee endpoints.
class EmployeeApiService {
  EmployeeApiService(this._client);

  final ApiClient _client;

  String get environmentId => _client.environment.environmentId;

  /// `POST /api/employee/add` as `multipart/form-data`.
  ///
  /// Validates locally first. Any 2xx response is a successful registration,
  /// even when the live watch-list update failed (`liveWatchList: false`).
  Future<RegistrationResult> registerEmployee(
    EmployeeRegistration registration, {
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final errors = registration.validate();
    if (errors.isNotEmpty) {
      throw ApiException.local(errors.values.first, kind: ApiErrorKind.validation);
    }
    final res = await _client.postMultipart(
      ApiEndpoints.employeeAdd,
      registration.toFormData(),
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return RegistrationResult.fromJson(res.statusCode, res.data);
  }

  /// `GET /api/employee/list` with server-side paging, search and filtering.
  Future<EmployeePage> getEmployees(EmployeeQuery query, {CancelToken? cancelToken}) async {
    final res = await _client.get(
      ApiEndpoints.employeeList,
      query: query.toQueryParameters(),
      cancelToken: cancelToken,
    );
    return EmployeePage.fromJson(res.data);
  }

  /// Absolute URL for an employee's `photoUrl`, or `null` if there is none.
  String? resolvePhotoUrl(String? photoUrl) {
    if (photoUrl == null || photoUrl.trim().isEmpty) return null;
    return _client.resolveUrl(photoUrl);
  }

  Map<String, String> get photoHeaders => _client.imageHeaders;
}
