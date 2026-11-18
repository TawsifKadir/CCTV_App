import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One recorded request (admin builds only).
@immutable
class NetworkLogEntry {
  const NetworkLogEntry({
    required this.method,
    required this.url,
    required this.startedAt,
    this.status,
    this.durationMs,
    this.error,
    this.requestSummary,
    this.responsePreview,
  });

  final String method;
  final String url;
  final DateTime startedAt;
  final int? status;
  final int? durationMs;
  final String? error;

  /// Field names / file names only — never photo bytes.
  final String? requestSummary;

  /// First few KB of the response body, for API inspection.
  final String? responsePreview;

  bool get ok => status != null && status! >= 200 && status! < 300;
}

/// In-memory ring buffer of recent requests, shown in Diagnostics.
class NetworkLog extends ValueNotifier<List<NetworkLogEntry>> {
  NetworkLog({this.capacity = 100}) : super(const []);
  final int capacity;

  void add(NetworkLogEntry e) {
    final list = [e, ...value];
    value = list.length > capacity ? list.sublist(0, capacity) : list;
  }

  void clear() => value = const [];
}

/// Records requests into a [NetworkLog]. Installed in the HTTP client only
/// for admin builds (see apiClientProvider), so client builds never keep
/// request/response data.
class NetworkRecorderInterceptor extends Interceptor {
  NetworkRecorderInterceptor(this.log);
  final NetworkLog log;
  static const _key = '_enrolly_recorded_at';
  static const _maxPreview = 4096;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_key] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _record(response.requestOptions, response.statusCode, response.data, null);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(err.requestOptions, err.response?.statusCode, err.response?.data, err.type.name);
    handler.next(err);
  }

  void _record(RequestOptions o, int? status, Object? body, String? error) {
    final started = o.extra[_key] as DateTime? ?? DateTime.now();
    String? summary;
    final data = o.data;
    if (data is FormData) {
      summary = [
        for (final f in data.fields) '${f.key}=${f.value}',
        for (final f in data.files) '${f.key}=<file ${f.value.filename}, ${f.value.length} bytes>',
      ].join('\n');
    }
    // Never keep credentials or tokens, even in admin diagnostics.
    final isAuth = o.path.contains('/auth/');
    if (isAuth) summary = '[credentials redacted]';
    var preview = isAuth ? (body == null ? null : '[authentication response redacted]') : body?.toString();
    if (preview != null && preview.length > _maxPreview) preview = '${preview.substring(0, _maxPreview)}…';
    log.add(
      NetworkLogEntry(
        method: o.method,
        url: o.uri.toString(),
        startedAt: started,
        status: status,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        error: error,
        requestSummary: summary,
        responsePreview: preview,
      ),
    );
  }
}
