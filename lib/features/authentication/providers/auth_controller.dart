import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/services/providers.dart';
import '../../connectivity/connectivity_service.dart';
import '../../environments/presentation/providers/environment_providers.dart';
import '../data/auth_api_service.dart';
import '../../../core/config/app_features.dart';
import '../../../data/models/operator.dart';
import '../../connectivity/app_features_provider.dart';
import '../data/auth_session.dart';
import '../widgets/dev_login_tools.dart' show DemoAccount;

/// Session restored from secure storage at startup (overridden in `main()`).
final initialSessionProvider = Provider<AuthSession?>((ref) => null);

final authApiServiceProvider = Provider<AuthApiService>((ref) => AuthApiService(ref.watch(apiClientProvider)));

/// Current session, or `null` when signed out. Every build — production and
/// development — signs in through the backend; there is no local fallback.
class AuthController extends Notifier<AuthSession?> {
  String? _signOutReason;

  @override
  AuthSession? build() {
    final env = ref.read(activeEnvironmentProvider);
    // A session belongs to the backend that issued it.
    ref.listen(activeEnvironmentProvider, (prev, next) {
      final s = state;
      if (s != null && s.environmentId != next.environmentId) {
        logout(reason: 'You switched to ${next.environmentName}. Please sign in to that server.', notifyServer: false);
      }
    });
    final initial = ref.watch(initialSessionProvider);
    final restored = initial != null && initial.environmentId == env.environmentId && !initial.isExpired()
        ? initial
        : null;
    if (restored != null && !restored.isDemo) Future.microtask(checkAuthenticationStatus);
    return restored;
  }

  /// Confirms a restored session with `GET /api/auth/session`. A 401 signs
  /// out (via the client's unauthorized hook); if the server can't be
  /// reached the session is kept so the app stays usable offline.
  Future<void> checkAuthenticationStatus() async {
    final s = state;
    if (s == null || s.isDemo) return;
    try {
      final info = await ref.read(authApiServiceProvider).session();
      final current = state;
      if (current == null || current.isDemo) return;
      final role = info['role'];
      state = AuthSession(
        operator: Operator(
          username: (info['username'] as String?) ?? current.operator.username,
          id: current.operator.id,
          displayName: current.operator.displayName,
          email: current.operator.email,
          roles: role is String && role.isNotEmpty ? [role] : current.operator.roles,
        ),
        environmentId: current.environmentId,
        createdAt: current.createdAt,
        accessToken: current.accessToken,
        tokenType: current.tokenType,
        refreshToken: current.refreshToken,
        sessionId: current.sessionId,
        cookies: current.cookies,
        expiresAt: DateTime.tryParse(info['expiresAt'] as String? ?? '')?.toLocal() ?? current.expiresAt,
      );
    } catch (_) {
      // Offline or server error: keep the local session.
    }
  }

  Future<void> login(String username, String password, {required bool remember}) async {
    _signOutReason = null;
    if (!ref.read(connectionStatusProvider).device.hasNetwork) {
      // No offline authentication: a sign-in always needs the server.
      throw const ApiException.local(
        'Unable to connect to the server. Check your internet connection and try again.',
        kind: ApiErrorKind.noConnection,
      );
    }
    state = await ref
        .read(authRepositoryProvider)
        .login(ref.read(authApiServiceProvider), username, password, remember: remember);
  }

  /// Demo login (non-production only): validated on the device, no HTTP
  /// request, works offline, never persisted, and isolated from real data
  /// (see `dataScopeProvider` and the demo backend).
  void loginDemo(String username, String password) {
    if (kProductionBuild || !ref.read(appFeaturesProvider).adminMode) {
      throw StateError('Demo login is not available in this build.');
    }
    if (!DemoAccount.matches(username, password)) {
      throw const ApiException.local('Incorrect demo username or password.', kind: ApiErrorKind.unauthorized);
    }
    _signOutReason = null;
    ref.read(isDemoSessionProvider.notifier).set(true);
    state = AuthSession(
      operator: const Operator(username: DemoAccount.username, displayName: 'Demo User', roles: ['demo']),
      environmentId: ref.read(activeEnvironmentProvider).environmentId,
      createdAt: DateTime.now(),
      isDemo: true,
    );
  }

  Future<void> logout({String? reason, bool notifyServer = true}) async {
    final s = state;
    _signOutReason = reason;
    if (s != null && !s.isDemo) {
      // Tell the server while the credentials are still attached.
      if (notifyServer) {
        await ref.read(authApiServiceProvider).logout().timeout(const Duration(seconds: 5), onTimeout: () => false);
      }
      await ref.read(authRepositoryProvider).logout();
    }
    if (s?.isDemo ?? false) ref.read(isDemoSessionProvider.notifier).set(false);
    state = null;
  }

  /// Called when an authenticated request returns 401.
  void sessionExpired() {
    if (state == null) return;
    logout(reason: 'Your session has expired. Please sign in again.', notifyServer: false);
  }

  /// Why the user was signed out (shown once on the login screen).
  String? takeSignOutReason() {
    final r = _signOutReason;
    _signOutReason = null;
    return r;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(AuthController.new);

/// Maps sign-in errors to friendly text (never raw exceptions).
String friendlyAuthError(Object e) {
  if (e is ApiException) return e.message;
  return 'Sign-in failed. Please try again.';
}
