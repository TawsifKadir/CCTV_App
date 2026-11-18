import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

/// Where a remembered session is kept between launches.
abstract class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

/// Keychain (iOS), EncryptedSharedPreferences/Keystore (Android), encrypted
/// browser storage (web). If the platform refuses — e.g. browsers without
/// WebCrypto on plain-http origins — the session simply isn't remembered;
/// it is never written in clear text instead.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'enrolly.auth.session';

  @override
  Future<AuthSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return AuthSession.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('Stored session unavailable: ${e.runtimeType}');
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('Secure storage unavailable; session will not be remembered (${e.runtimeType})');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// For tests.
class MemorySessionStore implements SessionStore {
  AuthSession? value;

  @override
  Future<AuthSession?> read() async => value;

  @override
  Future<void> write(AuthSession session) async => value = session;

  @override
  Future<void> clear() async => value = null;
}
