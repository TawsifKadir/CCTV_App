import '../models/operator.dart';

export '../../core/network/api_exceptions.dart' show ApiException, ApiErrorKind;

/// Operator authentication contract.
///
/// The Spring Boot backend does not expose authentication endpoints yet, so
/// the app ships [DemoAuthApi] (on-device, clearly labelled as a demo). When
/// a real auth API exists, implement this interface with `ApiClient` and
/// swap it in `authApiProvider` (lib/core/services/providers.dart); screens
/// do not change. The HTTP client already supports an Authorization header
/// via `authHeaderProvider`.
abstract class AuthApi {
  Future<Operator> register(RegisterRequest request);
  Future<Operator> login(String email, String password);
  Future<void> requestPasswordReset(String email);
  Future<Operator> updateProfile(Operator operator);
}

class RegisterRequest {
  const RegisterRequest({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    this.organization,
  });

  final String fullName;
  final String email;
  final String phone;
  final String password;
  final String? organization;
}
