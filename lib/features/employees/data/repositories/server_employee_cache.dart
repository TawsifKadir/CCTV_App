import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/employee.dart';
import '../models/employee_page.dart';
import '../models/employee_query.dart';

/// Every server employee this device has seen, per environment, so records
/// can still be browsed and searched offline. Always shown with the time of
/// the last successful refresh — it is a cache, never presented as live.
class ServerEmployeeCache {
  ServerEmployeeCache(this._box, {required this.environmentId, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Box<dynamic> _box;
  final String environmentId;
  final DateTime Function() _clock;

  String get _prefix => 'e|$environmentId|';
  String get _refreshKey => 'refreshed|$environmentId';
  String get _totalKey => 'total|$environmentId';

  DateTime? get lastRefresh => DateTime.tryParse(_box.get(_refreshKey) as String? ?? '');

  /// Server total from the last unfiltered fetch.
  int? get lastKnownTotal => _box.get(_totalKey) as int?;

  /// Stores the records of a freshly fetched page.
  Future<void> upsertPage(EmployeePage page, EmployeeQuery query) async {
    final entries = <String, String>{
      for (final e in page.content)
        if (e.id != null) '$_prefix${e.id}': jsonEncode(e.toJson()),
    };
    if (entries.isNotEmpty) await _box.putAll(entries);
    await _box.put(_refreshKey, _clock().toIso8601String());
    if (query.query.trim().isEmpty && query.source == null) await _box.put(_totalKey, page.totalElements);
  }

  Future<void> upsert(Employee e) async {
    if (e.id == null) return;
    await _box.put('$_prefix${e.id}', jsonEncode(e.toJson()));
  }

  List<Employee> all() {
    final out = <Employee>[];
    for (final key in _box.keys) {
      if (key is! String || !key.startsWith(_prefix)) continue;
      try {
        out.add(Employee.fromJson(Map<String, dynamic>.from(jsonDecode(_box.get(key) as String) as Map)));
      } catch (_) {
        // skip corrupted rows
      }
    }
    // Newest enrolment first, then highest id.
    out.sort((a, b) {
      final t = (b.enrolledAt ?? DateTime(0)).compareTo(a.enrolledAt ?? DateTime(0));
      return t != 0 ? t : (b.id ?? 0).compareTo(a.id ?? 0);
    });
    return out;
  }

  Employee? byId(int id) {
    final raw = _box.get('$_prefix$id');
    if (raw is! String) return null;
    try {
      return Employee.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  /// Offline equivalent of the list endpoint: search, source filter and
  /// paging applied locally over cached records.
  EmployeePage query(EmployeeQuery q) {
    final text = q.query.trim().toLowerCase();
    final matches = all().where((e) {
      if (q.source != null && e.enrollmentSource != q.source) return false;
      return text.isEmpty || matchesSearch(e, text);
    }).toList();
    final size = q.size.clamp(1, 100);
    final totalPages = matches.isEmpty ? 0 : (matches.length + size - 1) ~/ size;
    final page = totalPages == 0 ? 0 : q.page.clamp(0, totalPages - 1);
    final start = page * size;
    return EmployeePage(
      content: matches.skip(start).take(size).toList(),
      page: page,
      size: size,
      totalElements: matches.length,
      totalPages: totalPages,
      hasPrevious: page > 0,
      hasNext: page + 1 < totalPages,
    );
  }

  int get count => _box.keys.where((k) => k is String && k.startsWith(_prefix)).length;

  Future<void> clear() async {
    final keys = _box.keys
        .where((k) => k is String && (k.startsWith(_prefix) || k == _refreshKey || k == _totalKey))
        .toList();
    await _box.deleteAll(keys);
  }
}

/// Same fields the server searches: number, name, designation, template ID.
bool matchesSearch(Employee e, String lowerText) =>
    e.name.toLowerCase().contains(lowerText) ||
    (e.designation?.toLowerCase().contains(lowerText) ?? false) ||
    (e.employeeNo?.toString().contains(lowerText) ?? false) ||
    (e.templateId?.toLowerCase().contains(lowerText) ?? false);
