import 'package:flutter/foundation.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../data/models/operator.dart';

/// An authenticated session with one backend environment.
///
/// Holds whatever the login response provided: a token, a server-side
/// session cookie, a session id — or none of these (then the backend relies
/// on something the app can't see, and only the operator info is kept).
@immutable
class AuthSession {
  const AuthSession({
    required this.operator,
    required this.environmentId,
    required this.createdAt,
    this.accessToken,
    this.tokenType,
    this.refreshToken,
    this.sessionId,
    this.cookies = const {},
    this.expiresAt,
    this.isDemo = false,
  });

  final Operator operator;

  /// Local demo session (non-production builds only): never sent to or
  /// accepted by a real backend.
  final bool isDemo;

  /// Sessions are tied to the backend that issued them.
  final String environmentId;
  final DateTime createdAt;
  final String? accessToken;
  final String? tokenType;

  /// Stored if returned; there is no refresh endpoint to use it yet.
  final String? refreshToken;
  final String? sessionId;

  /// Session cookies from `Set-Cookie` (e.g. JSESSIONID), sent back on
  /// native platforms. On the web the browser manages cookies itself.
  final Map<String, String> cookies;
  final DateTime? expiresAt;

  bool isExpired([DateTime? now]) => expiresAt != null && !(now ?? DateTime.now()).isBefore(expiresAt!);

  /// Headers that authenticate API requests.
  Map<String, String> get requestHeaders => isDemo
      ? const {}
      : {
          if (accessToken != null) 'Authorization': '${tokenType ?? 'Bearer'} $accessToken',
          if (cookies.isNotEmpty) 'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        };

  Map<String, dynamic> toJson() => {
    'operator': operator.toJson(),
    'environmentId': environmentId,
    'createdAt': createdAt.toIso8601String(),
    'accessToken': accessToken,
    'tokenType': tokenType,
    'refreshToken': refreshToken,
    'sessionId': sessionId,
    'cookies': cookies,
    'expiresAt': expiresAt?.toIso8601String(),
    'isDemo': isDemo,
  };

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
    operator: Operator.fromJson(Map<String, dynamic>.from(j['operator'] as Map)),
    environmentId: j['environmentId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    accessToken: j['accessToken'] as String?,
    tokenType: j['tokenType'] as String?,
    refreshToken: j['refreshToken'] as String?,
    sessionId: j['sessionId'] as String?,
    cookies: Map<String, String>.from(j['cookies'] as Map? ?? const {}),
    expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? ''),
    isDemo: j['isDemo'] as bool? ?? false,
  );
}

/// Parses `POST /api/auth/login` responses.
///
/// CONFIRMED (development server, 2026-11-17):
///   200 → {"token": "(JWT)", "role": "admin", "username": "kitbd",
///          "expiresIn": 1800} plus an HttpOnly `MONITRY_TOKEN` cookie
///          holding the same token. The app uses the token as a Bearer
///          header (which the server accepts and which needs no CSRF).
///   401 → {"message": "Invalid username or password."}
/// The other keys below are kept so minor backend changes don't break
/// sign-in.
class AuthResponseParser {
  AuthResponseParser._();

  static const tokenKeys = ['accessToken', 'access_token', 'token', 'jwt'];
  static const tokenTypeKeys = ['tokenType', 'token_type'];
  static const refreshTokenKeys = ['refreshToken', 'refresh_token'];
  static const sessionIdKeys = ['sessionId', 'session_id'];
  static const expiresInKeys = ['expiresIn', 'expires_in']; // seconds
  static const expiresAtKeys = ['expiresAt', 'expires_at']; // ISO date-time
  static const userKeys = ['user', 'operator', 'account', 'principal'];
  static const nameKeys = ['displayName', 'fullName', 'name'];
  static const roleKeys = ['roles', 'authorities', 'role'];

  /// Cookie names treated as the server session.
  static const sessionCookies = ['JSESSIONID', 'SESSION'];

  static AuthSession parse({
    required Object? body,
    required Map<String, List<String>> headers,
    required String enteredUsername,
    required String environmentId,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final j = body is Map ? Map<String, dynamic>.from(body) : const <String, dynamic>{};

    // An explicit failure flag inside a 2xx response is still a failure.
    if (j['success'] == false || j['authenticated'] == false) {
      throw ApiException(
        401,
        ApiException.messageFromBody(j) ?? 'Incorrect username or password.',
        kind: ApiErrorKind.unauthorized,
      );
    }

    String? str(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v is num) return '$v';
      }
      return null;
    }

    Map<String, dynamic> user = j;
    for (final k in userKeys) {
      if (j[k] is Map) {
        user = Map<String, dynamic>.from(j[k] as Map);
        break;
      }
    }

    final roles = <String>[];
    for (final k in roleKeys) {
      final v = user[k] ?? j[k];
      if (v is String && v.isNotEmpty) {
        roles.add(v);
        break;
      }
      if (v is List) {
        for (final r in v) {
          if (r is String) roles.add(r);
          if (r is Map && r['authority'] is String) roles.add(r['authority'] as String);
        }
        break;
      }
    }

    DateTime? expiresAt = DateTime.tryParse(str(j, expiresAtKeys) ?? '');
    final expiresIn = num.tryParse(str(j, expiresInKeys) ?? '');
    if (expiresAt == null && expiresIn != null) expiresAt = at.add(Duration(seconds: expiresIn.toInt()));

    return AuthSession(
      operator: Operator(
        username: str(user, const ['username', 'login']) ?? enteredUsername.trim(),
        id: str(user, const ['id', 'userId']),
        displayName: str(user, nameKeys),
        email: str(user, const ['email']),
        roles: roles,
      ),
      environmentId: environmentId,
      createdAt: at,
      accessToken: str(j, tokenKeys),
      tokenType: str(j, tokenTypeKeys),
      refreshToken: str(j, refreshTokenKeys),
      sessionId: str(j, sessionIdKeys),
      cookies: sessionCookiesFrom(headers),
      expiresAt: expiresAt,
    );
  }

  /// `name=value` of session cookies in `Set-Cookie` headers (attributes such
  /// as Path or HttpOnly are dropped).
  static Map<String, String> sessionCookiesFrom(Map<String, List<String>> headers) {
    final out = <String, String>{};
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'set-cookie') continue;
      for (final raw in entry.value) {
        final pair = raw.split(';').first.trim();
        final i = pair.indexOf('=');
        if (i <= 0) continue;
        final name = pair.substring(0, i);
        if (sessionCookies.contains(name)) out[name] = pair.substring(i + 1);
      }
    }
    return out;
  }
}
