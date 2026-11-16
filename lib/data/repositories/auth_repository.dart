import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/activity.dart';
import '../models/operator.dart';
import '../remote/api_contracts.dart';
import 'activity_repository.dart';

/// Coordinates the auth API with the locally persisted session.
///
/// Session rules:
/// * "Remember me" on  -> session survives app restarts.
/// * "Remember me" off -> session is discarded on the next cold start.
class AuthRepository {
  AuthRepository({
    required AuthApi api,
    required Box<dynamic> sessionBox,
    required ActivityRepository activity,
  })  : _api = api,
        _session = sessionBox,
        _activity = activity;

  final AuthApi _api;
  final Box<dynamic> _session;
  final ActivityRepository _activity;

  static const _kOperator = 'operator';
  static const _kPersistent = 'persistent';
  static const _kRememberedEmail = 'remembered_email';

  /// Restores the session at startup (call once before building the UI).
  Future<Operator?> restoreSession() async {
    final raw = _session.get(_kOperator);
    if (raw is! String) return null;
    final persistent = _session.get(_kPersistent) as bool? ?? false;
    if (!persistent) {
      await _session.delete(_kOperator);
      return null;
    }
    try {
      return Operator.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      await _session.delete(_kOperator);
      return null;
    }
  }

  String? get rememberedEmail => _session.get(_kRememberedEmail) as String?;

  Future<Operator> login(String email, String password, {required bool remember}) async {
    final op = await _api.login(email.trim(), password);
    await _persist(op, remember: remember);
    await _activity.log(ActivityType.login, '${op.fullName} signed in');
    return op;
  }

  Future<Operator> register(RegisterRequest request) async {
    final op = await _api.register(request);
    await _persist(op, remember: true);
    await _activity.log(ActivityType.registered, 'Operator account created',
        subtitle: op.fullName);
    return op;
  }

  Future<void> requestPasswordReset(String email) => _api.requestPasswordReset(email);

  Future<Operator> updateProfile(Operator op) async {
    final updated = await _api.updateProfile(op);
    final persistent = _session.get(_kPersistent) as bool? ?? true;
    await _persist(updated, remember: persistent);
    return updated;
  }

  Future<void> logout() async {
    await _session.delete(_kOperator);
    await _session.delete(_kPersistent);
  }

  Future<void> _persist(Operator op, {required bool remember}) async {
    await _session.put(_kOperator, jsonEncode(op.toJson()));
    await _session.put(_kPersistent, remember);
    if (remember) {
      await _session.put(_kRememberedEmail, op.email);
    } else {
      await _session.delete(_kRememberedEmail);
    }
  }
}
