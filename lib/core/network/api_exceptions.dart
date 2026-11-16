import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

enum ApiErrorKind {
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  payloadTooLarge,
  validation,
  server,
  httpError,
  connectionRefused,
  dns,
  timeout,
  noConnection,
  insecureConnection,
  invalidResponse,
  emptyResponse,
  cancelled,
  unknown;

  static ApiErrorKind fromStatus(int status) => switch (status) {
        400 => badRequest,
        401 => unauthorized,
        403 => forbidden,
        404 => notFound,
        409 => conflict,
        413 => payloadTooLarge,
        422 => validation,
        >= 500 && < 600 => server,
        _ => httpError,
      };

  /// The request never got an HTTP response.
  bool get isConnectivity =>
      this == connectionRefused || this == dns || this == timeout || this == noConnection || this == insecureConnection;
}

/// Error raised by API calls and request validation.
///
/// [message] is always safe to show to end users: it never contains stack
/// traces or raw exception text.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {ApiErrorKind? kind, this.mayHaveReachedServer = false})
      : _kind = kind;

  /// A failure without an HTTP status (network, parsing, client validation).
  const ApiException.local(this.message, {required ApiErrorKind kind, this.mayHaveReachedServer = false})
      : statusCode = 0,
        _kind = kind;

  /// `true` when the server may have received and processed the request
  /// even though the app saw a failure (e.g. a timeout while waiting for the
  /// response, a dropped connection mid-upload, a 5xx after processing, or
  /// a browser blocking the response). Retrying such a registration blindly
  /// could create a duplicate employee, so the sync engine reconciles first.
  final bool mayHaveReachedServer;

  /// Status code, or 0 when there was no HTTP response.
  final int statusCode;
  final String message;
  final ApiErrorKind? _kind;

  ApiErrorKind get kind => _kind ?? ApiErrorKind.fromStatus(statusCode);

  bool get isNetwork => kind.isConnectivity;

  @override
  String toString() => 'ApiException(${kind.name}${statusCode == 0 ? '' : ' $statusCode'}): $message';

  /// Pulls a user-facing message out of an error body.
  ///
  /// Handles the backend's `{"error": "..."}` shape and Spring Boot's default
  /// error document (`{"timestamp", "status", "error": "Bad Request",
  /// "message": "..."}`), where `error` is only the reason phrase.
  static String? serverMessage(Object? body) {
    Object? data = body;
    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return null;
      try {
        data = jsonDecode(s);
      } catch (_) {
        // Plain-text error bodies are shown only when short and not HTML.
        if (s.length <= 200 && !s.startsWith('<')) return s;
        return null;
      }
    }
    if (data is! Map) return null;
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final isSpringDefault = data.containsKey('timestamp') && data.containsKey('status');
    final message = text(data['message']);
    if (isSpringDefault) {
      if (message != null && message != 'No message available') return message;
      return null; // `error` is just "Bad Request" etc.
    }
    return text(data['error']) ?? message ?? text(data['detail']) ?? text(data['title']);
  }

  static String defaultMessage(ApiErrorKind kind, {String? server}) {
    final where = server ?? 'the server';
    return switch (kind) {
      ApiErrorKind.badRequest => 'The server rejected the request. Please check the details and try again.',
      ApiErrorKind.unauthorized => 'You are not authorised. Please sign in again.',
      ApiErrorKind.forbidden => 'You do not have permission to perform this action.',
      ApiErrorKind.notFound => 'The requested resource was not found on $where. Check the selected environment.',
      ApiErrorKind.conflict => 'This record conflicts with existing data on the server.',
      ApiErrorKind.payloadTooLarge =>
        'The photo is larger than the server accepts. Use a JPEG or PNG photo up to 10 MB.',
      ApiErrorKind.validation => 'Some of the submitted details are invalid.',
      ApiErrorKind.server => 'The server encountered an error. Please try again shortly.',
      ApiErrorKind.httpError => 'The server returned an unexpected response.',
      ApiErrorKind.connectionRefused => 'Could not connect to $where. Make sure the backend is running.',
      ApiErrorKind.dns => 'The server address for $where could not be found. Check the environment URL.',
      ApiErrorKind.timeout => '$where took too long to respond. Please try again.',
      ApiErrorKind.noConnection =>
        'Could not reach $where. Check the network connection and that the backend is running'
            '${server == null ? '' : ' (and allows requests from this app)'}.',
      ApiErrorKind.insecureConnection => 'A secure connection to $where could not be established.',
      ApiErrorKind.invalidResponse => 'The server sent a response the app could not read.',
      ApiErrorKind.emptyResponse => 'The server sent an empty response.',
      ApiErrorKind.cancelled => 'The request was cancelled.',
      ApiErrorKind.unknown => 'Something went wrong. Please try again.',
    };
  }

  /// Maps a Dio failure to an [ApiException] with a friendly message.
  factory ApiException.fromDio(DioException e) {
    final server = _serverLabel(e.requestOptions);
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        // Never connected: the request cannot have been processed.
        return ApiException.local(defaultMessage(ApiErrorKind.timeout, server: server), kind: ApiErrorKind.timeout);
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException.local(defaultMessage(ApiErrorKind.timeout, server: server),
            kind: ApiErrorKind.timeout, mayHaveReachedServer: true);
      case DioExceptionType.badCertificate:
        return ApiException.local(defaultMessage(ApiErrorKind.insecureConnection, server: server),
            kind: ApiErrorKind.insecureConnection);
      case DioExceptionType.cancel:
        return ApiException.local(defaultMessage(ApiErrorKind.cancelled),
            kind: ApiErrorKind.cancelled, mayHaveReachedServer: true);
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        final kind = ApiErrorKind.fromStatus(status);
        final fromServer = serverMessage(e.response?.data);
        // A 5xx may come after the server already saved the record.
        return ApiException(status, fromServer ?? defaultMessage(kind, server: server),
            kind: kind, mayHaveReachedServer: status >= 500);
      case DioExceptionType.connectionError:
        final kind = _classifyConnectionError(e.error);
        return ApiException.local(defaultMessage(kind, server: server),
            kind: kind, mayHaveReachedServer: _mayHaveReached(kind, e.error));
      case DioExceptionType.unknown:
        if (e.error is FormatException) {
          return const ApiException.local('The server sent a response the app could not read.',
              kind: ApiErrorKind.invalidResponse, mayHaveReachedServer: true);
        }
        if (e.error == null) {
          return ApiException.local(defaultMessage(ApiErrorKind.unknown), kind: ApiErrorKind.unknown);
        }
        // Dio reports most transport failures (e.g. on the web) as unknown.
        final kind = _classifyConnectionError(e.error);
        return ApiException.local(defaultMessage(kind, server: server),
            kind: kind, mayHaveReachedServer: _mayHaveReached(kind, e.error));
    }
  }

  /// Refused connections, DNS failures and TLS failures happen before any
  /// request data reaches the application. Anything else (a reset during
  /// upload, or — on the web — a response blocked by the browser, e.g. by
  /// CORS, after the server processed it) is treated as uncertain.
  static bool _mayHaveReached(ApiErrorKind kind, Object? error) {
    if (kind == ApiErrorKind.connectionRefused || kind == ApiErrorKind.dns || kind == ApiErrorKind.insecureConnection) {
      return false;
    }
    final s = (error?.toString() ?? '').toLowerCase();
    if (kIsWeb) return true; // the browser never says which stage failed
    // Connect-stage failures: nothing was sent.
    if (s.contains('network is unreachable') || s.contains('no route to host') || s.contains('connection failed')) {
      return false;
    }
    // Anything else (reset, closed, broken pipe, unknown) is uncertain. Being
    // conservative only costs a reconciliation lookup before the retry.
    return true;
  }

  static String _serverLabel(RequestOptions o) {
    try {
      return o.uri.origin;
    } catch (_) {
      return 'the server';
    }
  }

  /// `dart:io` is not available on the web, so classify by message text.
  static ApiErrorKind _classifyConnectionError(Object? error) {
    final s = (error?.toString() ?? '').toLowerCase();
    if (s.contains('connection refused') || s.contains('errno = 61') || s.contains('errno = 111')) {
      return ApiErrorKind.connectionRefused;
    }
    if (s.contains('failed host lookup') || s.contains('nodename nor servname') || s.contains('no address associated')) {
      return ApiErrorKind.dns;
    }
    if (s.contains('timed out')) return ApiErrorKind.timeout;
    if (s.contains('handshake') || s.contains('certificate')) return ApiErrorKind.insecureConnection;
    return ApiErrorKind.noConnection;
  }
}

/// Friendly text for any error thrown below the UI.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  return 'Something went wrong. Please try again.';
}
