import '../../../core/config/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import 'auth_session.dart';

/// `POST /api/auth/login` on the active environment, via the shared client.
///
/// `POST /api/auth/logout` ends the server session. There is no
/// session-check or refresh endpoint; expiry is detected by a 401.
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

  Future<AuthSession> login(String username, String password) async {
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
