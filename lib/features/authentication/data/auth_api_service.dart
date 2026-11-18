import '../../../core/config/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import 'auth_session.dart';

/// `POST /api/auth/login` on the active environment, via the shared client.
///
/// Confirmed on the server (2026-11-18): `GET /api/auth/csrf`,
/// `POST /api/auth/login`, `GET /api/auth/session`, `POST /api/auth/logout`.
/// There is no refresh endpoint; expiry is detected by `session` or a 401.
class AuthApiService {
  AuthApiService(this._client);
  final ApiClient _client;

  /// Best effort: `true` if the server confirmed the sign-out.
  Future<bool> logout() async {
    try {
      final res = await _client.postJson(ApiEndpoints.authLogout, const {});
      return res.data is Map && (res.data as Map)['signedOut'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the CSRF token the login POST needs (like the website does).
  /// Best effort: if it fails, the client retries the login once after the
  /// server's 403 issues a token.
  Future<void> _prepareCsrf() async {
    try {
      final res = await _client.get(ApiEndpoints.authCsrf);
      final d = res.data;
      if (d is Map && d['headerName'] is String && d['token'] is String) {
        _client.csrf.useEndpointToken(d['headerName'] as String, d['token'] as String);
      }
    } catch (_) {}
  }

  /// `GET /api/auth/session` for the current credentials.
  Future<Map<String, dynamic>> session() async {
    final res = await _client.get(ApiEndpoints.authSession);
    return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const {};
  }

  Future<AuthSession> login(String username, String password) async {
    await _prepareCsrf();
    try {
      final res = await _client.postJson(ApiEndpoints.authLogin, {'username': username, 'password': password});
      return AuthResponseParser.parse(
        body: res.data,
        headers: res.headers,
        enteredUsername: username,
        environmentId: _client.environment.environmentId,
      );
    } on ApiException catch (e) {
      throw ApiException(e.statusCode, loginErrorMessage(e), kind: e.kind, serverMessage: e.serverMessage);
    }
  }
}

/// Friendly sign-in messages. Raw errors are never shown.
String loginErrorMessage(ApiException e) => switch (e.kind) {
  ApiErrorKind.unauthorized => 'Incorrect username or password.',
  ApiErrorKind.badRequest || ApiErrorKind.validation => e.serverMessage ?? 'Enter a valid username and password.',
  ApiErrorKind.forbidden => e.serverMessage ?? 'This account is not allowed to sign in.',
  ApiErrorKind.notFound => 'The sign-in service was not found on this server. Check the selected environment.',
  ApiErrorKind.server ||
  ApiErrorKind.httpError => 'The authentication service is currently unavailable. Please try again later.',
  ApiErrorKind.timeout => 'The server took too long to respond. Please try again.',
  ApiErrorKind.invalidResponse ||
  ApiErrorKind.emptyResponse => 'The server sent an unexpected response. Please try again later.',
  ApiErrorKind.connectionRefused ||
  ApiErrorKind.dns ||
  ApiErrorKind.noConnection ||
  ApiErrorKind.insecureConnection => 'Unable to connect to the server. Check your internet connection and try again.',
  _ => 'Sign-in failed. Please try again.',
};
