import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Supplies the `Authorization` header value (e.g. `Bearer <token>`), or
/// `null` when no credentials are needed. The employee endpoints are
/// currently unauthenticated, so the app passes `null`; a real auth API can
/// plug a token in here later without touching any service.
typedef AuthHeaderProvider = String? Function();

class AuthHeaderInterceptor extends Interceptor {
  AuthHeaderInterceptor(this._provider);
  final AuthHeaderProvider _provider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final value = _provider();
    if (value != null && value.isNotEmpty) options.headers['Authorization'] = value;
    handler.next(options);
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
    final uri = o.uri.replace(queryParameters: o.uri.queryParameters.isEmpty ? null : {
      for (final k in o.uri.queryParameters.keys) k: '…',
    });
    debugPrint('[api] ${o.method} $uri → ${status ?? failure} (${ms}ms)');
  }
}
