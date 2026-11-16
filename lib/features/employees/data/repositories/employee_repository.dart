import 'package:dio/dio.dart';

import '../../../registration/domain/employee_registration.dart';
import '../models/employee.dart';
import '../models/employee_page.dart';
import '../models/employee_query.dart';
import '../models/registration_result.dart';
import '../services/employee_api_service.dart';

/// Employee data access with a short-lived, environment-scoped page cache.
///
/// The backend is the source of truth: cached pages only avoid refetching
/// when navigating back and forth, and are dropped after a registration or
/// an environment switch. Cache keys include the environment id so records
/// from one server can never be served for another.
class EmployeeRepository {
  EmployeeRepository({
    required EmployeeApiService api,
    this.cacheTtl = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : _api = api,
        _clock = clock ?? DateTime.now;

  final EmployeeApiService _api;
  final Duration cacheTtl;
  final DateTime Function() _clock;
  final _cache = <String, ({DateTime at, EmployeePage page})>{};

  String get environmentId => _api.environmentId;

  String cacheKeyFor(EmployeeQuery q) => '$environmentId|${q.cacheKey}';

  Future<EmployeePage> getEmployees(EmployeeQuery query, {bool forceRefresh = false, CancelToken? cancelToken}) async {
    final key = cacheKeyFor(query);
    final hit = _cache[key];
    if (!forceRefresh && hit != null && _clock().difference(hit.at) < cacheTtl) return hit.page;
    final page = await _api.getEmployees(query, cancelToken: cancelToken);
    _cache[key] = (at: _clock(), page: page);
    return page;
  }

  Future<RegistrationResult> registerEmployee(
    EmployeeRegistration registration, {
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final result = await _api.registerEmployee(registration, onSendProgress: onSendProgress, cancelToken: cancelToken);
    invalidate();
    return result;
  }

  /// Looks an employee up in cached pages (there is no single-employee API).
  Employee? findCached(String key) {
    for (final entry in _cache.values) {
      for (final e in entry.page.content) {
        if (e.key == key) return e;
      }
    }
    return null;
  }

  void invalidate() => _cache.clear();

  String? resolvePhotoUrl(String? photoUrl) => _api.resolvePhotoUrl(photoUrl);
  Map<String, String> get photoHeaders => _api.photoHeaders;
}
