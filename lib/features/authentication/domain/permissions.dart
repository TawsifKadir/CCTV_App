import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_session.dart';
import '../providers/auth_controller.dart';

/// What the signed-in user may do in the app.
///
/// The backend returns a single `role` string at login and from
/// `GET /api/auth/session`. Observed value: `admin`. Any other role is
/// treated as a standard (non-admin) user.
///
/// This only shapes the UI and client-side routing. Real authorization must
/// be enforced by the backend for every endpoint.
@immutable
class Permissions {
  const Permissions({required this.isAdmin, this.roleLabel = ''});

  factory Permissions.of(AuthSession? s) {
    final roles = s?.operator.roles ?? const <String>[];
    final admin = roles.any((r) {
      final v = r.trim().toLowerCase();
      return v == 'admin' || v == 'role_admin' || v == 'administrator';
    });
    final first = roles.isEmpty ? '' : roles.first.trim();
    return Permissions(
      isAdmin: admin,
      roleLabel: admin
          ? 'Administrator'
          : first.isEmpty
          ? 'User'
          : '${first[0].toUpperCase()}${first.substring(1).toLowerCase()}',
    );
  }

  final bool isAdmin;
  final String roleLabel;

  bool get canRegisterEmployees => true;
  bool get canViewEmployees => true;
  bool get canEditEmployees => isAdmin;
  bool get canDeleteEmployees => isAdmin;
}

final permissionsProvider = Provider<Permissions>((ref) => Permissions.of(ref.watch(authControllerProvider)));

/// Admin-only employee actions. Edit/delete endpoints are not confirmed on
/// the backend yet, so these explain that instead of sending requests.
/// Each handler re-checks the permission — hiding a button is not enough.
Future<void> requestEditEmployee(BuildContext context, Permissions p) async {
  if (!p.canEditEmployees) return;
  await _notAvailable(
    context,
    'Edit employee',
    'Employee editing is not currently available. This feature will be enabled in a future update.',
  );
}

Future<void> requestDeleteEmployee(BuildContext context, Permissions p) async {
  if (!p.canDeleteEmployees) return;
  await _notAvailable(
    context,
    'Delete employee',
    'Employee deletion is not currently available. This feature will be enabled in a future update.',
  );
}

Future<void> _notAvailable(BuildContext context, String title, String message) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    key: const Key('feature-unavailable'),
    title: Text(title),
    content: Text(message),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
  ),
);
