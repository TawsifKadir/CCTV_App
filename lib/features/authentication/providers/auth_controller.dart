import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/providers.dart';
import '../../../data/models/operator.dart';
import '../../../data/remote/api_contracts.dart';

/// Operator restored from storage at startup (overridden in `main()`).
final initialOperatorProvider = Provider<Operator?>((ref) => null);

/// Currently signed-in operator, or `null` when signed out.
class AuthController extends Notifier<Operator?> {
  @override
  Operator? build() => ref.watch(initialOperatorProvider);

  Future<void> login(String email, String password, {required bool remember}) async {
    state = await ref.read(authRepositoryProvider).login(email, password, remember: remember);
  }

  Future<void> register(RegisterRequest request) async {
    state = await ref.read(authRepositoryProvider).register(request);
  }

  Future<void> updateProfile({required String fullName, required String phone, String? organization}) async {
    final current = state;
    if (current == null) return;
    state = await ref.read(authRepositoryProvider).updateProfile(
          current.copyWith(fullName: fullName, phone: phone, organization: organization),
        );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = null;
  }
}

final authControllerProvider = NotifierProvider<AuthController, Operator?>(AuthController.new);

/// Maps backend/auth errors to friendly text.
String friendlyAuthError(Object e) {
  if (e is ApiException) return e.message;
  return 'Something went wrong. Please try again.';
}
