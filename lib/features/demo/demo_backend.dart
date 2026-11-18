import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

/// DEVELOPMENT / QA ONLY — installed in the HTTP client only during a demo
/// session, behind `!kProductionBuild` (compiled out of production).
///
/// A simulated backend answering the same endpoints from a separate local
/// box, so demo registrations exercise the real registration and sync code
/// but can never reach a real server. Photos are not stored here (the app
/// shows the device copy).
class DemoBackendAdapter implements HttpClientAdapter {
  DemoBackendAdapter(this._box);

  final Box<dynamic> _box;

  /// Diagnostics toggle: simulate an unreachable server.
  static bool serverDown = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (requestStream != null) await requestStream.drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (serverDown) {
      throw DioException.connectionError(requestOptions: o, reason: 'Connection refused (demo server is down)');
    }
    final path = o.path;
    if (path.endsWith('/auth/logout')) return _json(200, {'signedOut': true});
    if (path.endsWith('/employee/add') && o.data is FormData) return _add(o.data as FormData);
    if (path.endsWith('/employee/list')) return _list(o.queryParameters);
    return _json(404, {'status': 404, 'error': 'Not Found', 'timestamp': DateTime.now().toIso8601String()});
  }

  List<Map<String, dynamic>> _all() => [
    for (final v in _box.values)
      if (v is String) Map<String, dynamic>.from(jsonDecode(v) as Map),
  ]..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));

  ResponseBody _add(FormData form) {
    final f = {for (final e in form.fields) e.key: e.value};
    if (form.files.every((e) => e.key != 'photo')) {
      return _json(400, {'error': 'Upload a JPEG or PNG photo up to 10 MB.'});
    }
    if (DateTime.tryParse(f['dateOfBirth'] ?? '') == null) return _json(400, {'error': 'Enter a valid date of birth.'});
    final id = (_box.get('_next') as int? ?? 1);
    _box.put('_next', id + 1);
    final e = {
      'id': id,
      'employeeNo': id,
      'name': f['name'],
      'dateOfBirth': f['dateOfBirth'],
      'designation': f['designation'],
      'templateId': 'demo-template-$id',
      'templateBytes': 0,
      'enrolledAt': DateTime.now().toIso8601String(),
      'photoUrl': null,
      'enrollmentSource': 'photo',
    };
    _box.put('e$id', jsonEncode(e));
    return _json(201, {...e, 'liveWatchList': false, 'warning': 'Demo mode: no recognition engine.'});
  }

  ResponseBody _list(Map<String, dynamic> q) {
    final page = (q['page'] as int?) ?? 0;
    final size = (q['size'] as int?) ?? 24;
    final text = (q['query'] as String?)?.toLowerCase();
    final source = q['source'] as String?;
    final matches = _all()
        .where((e) => source == null || e['enrollmentSource'] == source)
        .where(
          (e) => text == null || '${e['name']} ${e['designation']} ${e['employeeNo']}'.toLowerCase().contains(text),
        )
        .toList();
    final pages = matches.isEmpty ? 0 : (matches.length + size - 1) ~/ size;
    return _json(200, {
      'content': matches.skip(page * size).take(size).toList(),
      'page': page,
      'size': size,
      'totalElements': matches.length,
      'totalPages': pages,
      'hasPrevious': page > 0,
      'hasNext': page + 1 < pages,
    });
  }

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}
