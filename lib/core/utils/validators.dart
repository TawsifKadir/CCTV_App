/// Form validators. Each returns `null` when valid, otherwise a friendly
/// message suitable for display under a field.
class Validators {
  Validators._();

  static final _emailRe = RegExp(r"^[\w.+\-']+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$");

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Full name is required';
    if (v.length < 3) return 'Name looks too short';
    if (v.length > 80) return 'Name must be under 80 characters';
    if (!RegExp(r"^[\p{L} .'\-]+$", unicode: true).hasMatch(v)) {
      return 'Use letters, spaces, apostrophes or hyphens only';
    }
    return null;
  }

  static String? email(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Email address is required' : null;
    if (!_emailRe.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Accepts international formats: optional leading +, 8–15 digits, with
  /// spaces, dashes, dots or parentheses as separators.
  static String? phone(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Phone number is required' : null;
    if (!RegExp(r'^\+?[\d\s\-().]+$').hasMatch(v)) {
      return 'Phone number can contain digits, spaces, + ( ) - only';
    }
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) {
      return 'Enter 8 to 15 digits';
    }
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add at least one uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Add at least one lowercase letter';
    if (!RegExp(r'\d').hasMatch(v)) return 'Add at least one number';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }
}
