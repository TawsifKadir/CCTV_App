import 'package:flutter/foundation.dart';

/// The signed-in operator (staff member using the app), as reported by the
/// backend's login response. Only [username] is guaranteed.
@immutable
class Operator {
  const Operator({required this.username, this.id, this.displayName, this.email, this.roles = const []});

  final String username;
  final String? id;
  final String? displayName;
  final String? email;
  final List<String> roles;

  String get fullName => (displayName == null || displayName!.trim().isEmpty) ? username : displayName!;

  Map<String, dynamic> toJson() => {
    'username': username,
    'id': id,
    'displayName': displayName,
    'email': email,
    'roles': roles,
  };

  factory Operator.fromJson(Map<String, dynamic> j) => Operator(
    username: j['username'] as String? ?? '',
    id: j['id'] as String?,
    displayName: j['displayName'] as String?,
    email: j['email'] as String?,
    roles: [for (final r in (j['roles'] as List? ?? const [])) '$r'],
  );
}
