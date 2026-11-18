import 'package:flutter/foundation.dart';

import '../../../../core/config/api_endpoints.dart';
import 'employee.dart';

/// Parameters for `GET /api/employee/list`.
@immutable
class EmployeeQuery {
  const EmployeeQuery({this.page = 0, this.size = ApiEndpoints.defaultPageSize, this.query = '', this.source});

  final int page;
  final int size;

  /// Free-text search (employee number, name, designation, template ID).
  final String query;

  /// `null` = all sources (the parameter is omitted).
  final EnrollmentSource? source;

  /// Query parameters exactly as the backend expects them. Empty search and
  /// "all sources" are omitted rather than sent as empty strings.
  Map<String, dynamic> toQueryParameters() {
    final q = query.trim();
    return {
      'page': page < 0 ? 0 : page,
      'size': size.clamp(1, ApiEndpoints.maxPageSize),
      if (q.isNotEmpty) 'query': q,
      if (source != null) 'source': source!.apiValue,
    };
  }

  /// Key used for caching (combined with the environment id by the
  /// repository).
  String get cacheKey {
    final p = toQueryParameters();
    return 'p=${p['page']}&s=${p['size']}&q=${p['query'] ?? ''}&src=${p['source'] ?? ''}';
  }

  EmployeeQuery copyWith({int? page, int? size, String? query, EnrollmentSource? Function()? source}) => EmployeeQuery(
    page: page ?? this.page,
    size: size ?? this.size,
    query: query ?? this.query,
    source: source == null ? this.source : source(),
  );

  @override
  bool operator ==(Object other) => other is EmployeeQuery && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'EmployeeQuery($cacheKey)';
}
