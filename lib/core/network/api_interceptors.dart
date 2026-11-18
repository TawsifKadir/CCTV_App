import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Supplies the current session's authentication headers (`Authorization`
/// and/or `Cookie`), or an empty map when signed out. Read on every request,
/// so every service using the shared client is authenticated the same way.
typedef AuthHeaderProvider = Map<String, String> Function();

class AuthHeaderInterceptor extends Interceptor {
  AuthHeaderInterceptor(this._provider);
  final AuthHeaderProvider _provider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // A sign-in never carries a previous session's credentials.
    if (!options.path.endsWith('/auth/login')) options.headers.addAll(_provider());
    handler.next(options);
  }
}

/// Reports 401 responses on authenticated requests (expired or invalid
/// session). The login request itself is excluded: there 401 just means
/// wrong credentials.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor(this.onUnauthorized);
  final void Function() onUnauthorized;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 && !err.requestOptions.path.endsWith('/auth/login')) onUnauthorized();
    handler.next(err);
  }
}

/// Spring Security CSRF (cookie-based `XSRF-TOKEN`): keeps the token from
/// `Set-Cookie` and echoes it as cookie + `X-XSRF-TOKEN` header on unsafe
/// requests that aren't bearer-authenticated (e.g. login). When a request is
/// rejected with 403 and a fresh token arrives with that response, it is
/// retried once — the first login on a new connection works that way.
///
/// On the web the browser owns cookies; cross-origin CSRF then depends on
/// the backend's CORS/CSRF configuration.
class CsrfInterceptor extends Interceptor {
  CsrfInterceptor(this._dio);
  final Dio _dio;
  String? token;
  static const _retried = '_csrf_retried';

  bool _applies(RequestOptions o) =>
      o.method != 'GET' &&
      o.method != 'HEAD' &&
      !(o.headers['Authorization']?.toString().startsWith('Bearer') ?? false);

  void _capture(Headers headers) {
    for (final raw in headers.map['set-cookie'] ?? const <String>[]) {
      final pair = raw.split(';').first.trim();
      if (pair.startsWith('XSRF-TOKEN=')) {
        final v = pair.substring('XSRF-TOKEN='.length);
        token = v.isEmpty ? null : v;
      }
    }
  }

  void _attach(RequestOptions o) {
    final t = token;
    if (t == null || !_applies(o)) return;
    o.headers['X-XSRF-TOKEN'] = t;
    final existing = o.headers['Cookie']?.toString();
    o.headers['Cookie'] = [if (existing != null && existing.isNotEmpty) existing, 'XSRF-TOKEN=$t'].join('; ');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _attach(options);
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _capture(response.headers);
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    if (res == null) return handler.next(err);
    final before = token;
    _capture(res.headers);
    final o = err.requestOptions;
    if (res.statusCode == 403 && _applies(o) && token != null && token != before && o.extra[_retried] != true) {
      o.extra[_retried] = true; // the retry passes through onRequest, which attaches the token
      try {
        return handler.resolve(await _dio.fetch<dynamic>(o));
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}

/// Reports reachability to the connection-status tracker.
///
/// Any HTTP response (even 4xx) proves the server is reachable; only
/// transport failures count as "offline".
class ConnectionTrackingInterceptor extends Interceptor {
  ConnectionTrackingInterceptor({required this.onReachable, required this.onUnreachable});

  final void Function() onReachable;
  final void Function(DioException error) onUnreachable;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    onReachable();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) {
      onReachable();
    } else if (err.type != DioExceptionType.cancel) {
      onUnreachable(err);
    }
    handler.next(err);
  }
}

/// Debug-only request log: method, URL, status and duration.
///
/// Bodies and headers are never logged, so photographs, personal details and
/// credentials cannot leak into logs.
class SafeLogInterceptor extends Interceptor {
  static const _startKey = '_enrolly_started_at';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode, failure: err.type.name);
    handler.next(err);
  }

  void _log(RequestOptions o, int? status, {String? failure}) {
    if (!kDebugMode) return;
    final started = o.extra[_startKey] as int?;
    final ms = started == null ? '?' : '${DateTime.now().millisecondsSinceEpoch - started}';
    // Query values may contain search text typed by operators; log keys only.
    final uri = o.uri.replace(
      queryParameters: o.uri.queryParameters.isEmpty ? null : {for (final k in o.uri.queryParameters.keys) k: '…'},
    );
    debugPrint('[api] ${o.method} $uri → ${status ?? failure} (${ms}ms)');
  }
}
