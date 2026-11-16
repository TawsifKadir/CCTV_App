import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/password_hasher.dart';
import '../models/operator.dart';
import 'api_contracts.dart';

/// DEMO operator authentication, verified on this device.
///
/// The employee APIs on the Spring Boot backend are real; operator sign-in
/// is not, because the backend has no auth endpoints yet. Accounts live in a
/// local Hive box with salted PBKDF2 password hashes. Replace this class
/// with an HTTP implementation of [AuthApi] when the backend provides one.
class DemoAuthApi implements AuthApi {
  DemoAuthApi(this._operators);

  final Box<dynamic> _operators;
  static const _uuid = Uuid();

  String _key(String email) => email.trim().toLowerCase();

  @override
  Future<Operator> register(RegisterRequest r) async {
    final key = _key(r.email);
    if (_operators.containsKey(key)) {
      throw const ApiException(409, 'An account with this email already exists');
    }
    final op = Operator(
      id: _uuid.v4(),
      fullName: r.fullName.trim(),
      email: key,
      phone: r.phone.trim(),
      organization: (r.organization?.trim().isEmpty ?? true) ? null : r.organization!.trim(),
      createdAt: DateTime.now(),
    );
    await _save(op, PasswordHasher.hash(r.password));
    return op;
  }

  @override
  Future<Operator> login(String email, String password) async {
    final raw = _operators.get(_key(email));
    if (raw is! String) throw const ApiException(401, 'Incorrect email or password');
    final record = jsonDecode(raw) as Map<String, dynamic>;
    if (!PasswordHasher.verify(password, record['passwordHash'] as String)) {
      throw const ApiException(401, 'Incorrect email or password');
    }
    return Operator.fromJson(Map<String, dynamic>.from(record['operator'] as Map));
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    // Demo: nothing is sent. Intentionally does not reveal whether the
    // account exists.
  }

  @override
  Future<Operator> updateProfile(Operator operator) async {
    final key = _key(operator.email);
    final raw = _operators.get(key);
    if (raw is! String) throw const ApiException(404, 'Account not found');
    final record = jsonDecode(raw) as Map<String, dynamic>;
    record['operator'] = operator.toJson();
    await _operators.put(key, jsonEncode(record));
    return operator;
  }

  bool hasOperator(String email) => _operators.containsKey(_key(email));

  /// Creates the demo operator on first launch.
  Future<void> ensureDemoOperator() async {
    if (hasOperator(AppConstants.demoEmail)) return;
    await _save(demoOperator, PasswordHasher.hash(AppConstants.demoPassword));
  }

  Future<void> _save(Operator op, String hash) =>
      _operators.put(_key(op.email), jsonEncode({'operator': op.toJson(), 'passwordHash': hash}));

  static final demoOperator = Operator(
    id: 'demo-operator',
    fullName: AppConstants.demoOperatorName,
    email: AppConstants.demoEmail,
    phone: '+1 555 010 2030',
    organization: AppConstants.demoOrganization,
    createdAt: DateTime(2026, 1, 5),
  );
}
