import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exceptions.dart';
import 'employee.dart';

/// One page of `GET /api/employee/list`.
@immutable
class EmployeePage {
  const EmployeePage({
    required this.content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
    required this.hasPrevious,
    required this.hasNext,
  });

  final List<Employee> content;

  /// Zero-based page index.
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool hasPrevious;
  final bool hasNext;

  bool get isEmpty => content.isEmpty;

  /// 1-based index of the first record on this page (0 when empty).
  int get firstItemNumber => content.isEmpty ? 0 : page * size + 1;
  int get lastItemNumber => content.isEmpty ? 0 : page * size + content.length;

  static const empty = EmployeePage(
    content: [],
    page: 0,
    size: 0,
    totalElements: 0,
    totalPages: 0,
    hasPrevious: false,
    hasNext: false,
  );

  /// Tolerant parser. Missing paging fields are derived from what is present;
  /// a body that is not an object, or whose `content` is not a list, is
  /// rejected as an invalid response.
  factory EmployeePage.fromJson(Object? json) {
    if (json == null) {
      throw const ApiException.local('The server sent an empty employee list response.',
          kind: ApiErrorKind.emptyResponse);
    }
    if (json is! Map) {
      throw const ApiException.local('The employee list response has an unexpected format.',
          kind: ApiErrorKind.invalidResponse);
    }
    final j = Map<String, dynamic>.from(json);
    final rawContent = j['content'] ?? const [];
    if (rawContent is! List) {
      throw const ApiException.local('The employee list response has an unexpected format.',
          kind: ApiErrorKind.invalidResponse);
    }
    final content = <Employee>[
      for (final item in rawContent)
        if (item is Map) Employee.fromJson(Map<String, dynamic>.from(item)),
    ];
    final page = parseInt(j['page']) ?? parseInt(j['number']) ?? 0;
    final size = parseInt(j['size']) ?? content.length;
    final total = parseInt(j['totalElements']) ?? content.length;
    final totalPages = parseInt(j['totalPages']) ?? (size <= 0 ? (total > 0 ? 1 : 0) : (total + size - 1) ~/ size);
    return EmployeePage(
      content: List.unmodifiable(content),
      page: page,
      size: size,
      totalElements: total,
      totalPages: totalPages,
      hasPrevious: parseBool(j['hasPrevious']) ?? page > 0,
      hasNext: parseBool(j['hasNext']) ?? page + 1 < totalPages,
    );
  }
}
