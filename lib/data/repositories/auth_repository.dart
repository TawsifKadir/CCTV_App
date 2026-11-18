import 'package:hive_ce/hive.dart';

import '../../features/authentication/data/auth_api_service.dart';
import '../../features/authentication/data/auth_session.dart';
import '../../features/authentication/data/session_store.dart';
import '../models/activity.dart';
import 'activity_repository.dart';

/// Coordinates the login API with the persisted session.
///
/// * "Remember me" on  → the session (token/cookie) is kept in secure
///   storage and restored on the next launch.
/// * "Remember me" off → the session lives in memory only.
/// Only the username (not the password) is remembered for convenience.
class AuthRepository {
  AuthRepository({required SessionStore store, required Box<dynamic> prefs, required ActivityRepository activity})
    : _store = store,
      _prefs = prefs,
      _activity = activity;

  final SessionStore _store;
  final Box<dynamic> _prefs;
  final ActivityRepository _activity;
  static const _kUsername = 'remembered_username';

  String? get rememberedUsername => _prefs.get(_kUsername) as String?;

  /// Restores a remembered session if it is still usable for
  /// [environmentId]. There is no server endpoint to validate it, so an
  /// invalid session is detected by the first 401 response instead.
  Future<AuthSession?> checkAuthenticationStatus(String environmentId) async {
    final s = await _store.read();
    if (s == null) return null;
    if (s.isExpired() || s.environmentId != environmentId) {
      await _store.clear();
      return null;
    }
    return s;
  }

  Future<AuthSession> login(AuthApiService api, String username, String password, {required bool remember}) async {
    final session = await api.login(username.trim(), password);
    await persistAuthenticationSession(session, remember: remember);
    await _activity.log(
      ActivityType.login,
      '${session.operator.fullName} signed in',
      environmentId: session.environmentId,
    );
    return session;
  }

  Future<void> persistAuthenticationSession(AuthSession session, {required bool remember}) async {
    if (remember) {
      await _store.write(session);
      await _prefs.put(_kUsername, session.operator.username);
    } else {
      await _store.clear();
      await _prefs.delete(_kUsername);
    }
  }

  /// Client-side logout: forgets the token/cookie. The backend has no logout
  /// endpoint, so a server-side session is not invalidated by this.
  Future<void> logout() => _store.clear();
}
