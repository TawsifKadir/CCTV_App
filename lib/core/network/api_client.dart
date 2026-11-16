import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/environment_config.dart';
import 'api_exceptions.dart';
import 'api_interceptors.dart';

/// A decoded JSON response.
class ApiResponse {
  const ApiResponse(this.statusCode, this.data);
  final int statusCode;

  /// Decoded JSON (`Map`, `List`, …) or `null` for an empty body.
  final Object? data;
}

/// Thin wrapper around [Dio] bound to one [EnvironmentConfig].
///
/// A new client is created whenever the active environment changes, so a
/// request can never be sent to one server with another server's base URL.
class ApiClient {
  ApiClient({
    required this.environment,
    Dio? dio,
    AuthHeaderProvider? authHeader,
    void Function()? onReachable,
    void Function(DioException error)? onUnreachable,
    bool logRequests = false,
  })  : _authHeader = authHeader,
        dio = dio ?? Dio() {
    this.dio.options
      ..baseUrl = environment.apiBaseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 30)
      // Bodies are decoded here so invalid JSON and empty bodies can be
      // reported precisely, and error bodies are always available.
      ..responseType = ResponseType.plain
      ..headers['Accept'] = 'application/json';
    this.dio.interceptors.addAll([
      if (authHeader != null) AuthHeaderInterceptor(authHeader),
      if (onReachable != null || onUnreachable != null)
        ConnectionTrackingInterceptor(
          onReachable: onReachable ?? () {},
          onUnreachable: onUnreachable ?? (_) {},
        ),
      if (logRequests) SafeLogInterceptor(),
    ]);
  }

  final EnvironmentConfig environment;
  final Dio dio;
  final AuthHeaderProvider? _authHeader;

  /// Headers for requests made outside Dio (e.g. `Image.network`).
  Map<String, String> get imageHeaders {
    final auth = _authHeader?.call();
    return auth == null || auth.isEmpty ? const {} : {'Authorization': auth};
  }

  /// Absolute URL for a server-provided path such as `/api/employee/1/photo`.
  String resolveUrl(String pathOrUrl) => environment.resolveUrl(pathOrUrl);

  Future<ApiResponse> get(String path, {Map<String, dynamic>? query, CancelToken? cancelToken}) =>
      _send(() => dio.get<String>(path, queryParameters: query, cancelToken: cancelToken));

  /// Sends `multipart/form-data`. Dio sets the boundary header from [data].
  Future<ApiResponse> postMultipart(
    String path,
    FormData data, {
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) =>
      _send(() => dio.post<String>(
            path,
            data: data,
            options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
            onSendProgress: onSendProgress,
            cancelToken: cancelToken,
          ));

  Future<ApiResponse> _send(Future<Response<String>> Function() request) async {
    final Response<String> response;
    try {
      response = await request();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
    return ApiResponse(response.statusCode ?? 0, decodeJson(response.data));
  }

  /// Decodes a JSON body. `null` for an empty body.
  static Object? decodeJson(String? body) {
    if (body == null || body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const ApiException.local('The server sent a response the app could not read.',
          kind: ApiErrorKind.invalidResponse);
    }
  }

  void close() => dio.close(force: true);
}
