import 'package:cctv_app/core/utils/validators.dart';
import 'package:cctv_app/features/registration/domain/employee_registration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Operator form validation', () {
    test('full name', () {
      expect(Validators.fullName(''), isNotNull);
      expect(Validators.fullName('Al'), isNotNull);
      expect(Validators.fullName('R2-D2 #1'), isNotNull);
      expect(Validators.fullName("Zoë O'Neil-Ávila"), isNull);
    });

    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('', required: false), isNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('jane.doe+tag@example.co.uk'), isNull);
    });

    test('phone', () {
      expect(Validators.phone(''), isNotNull);
      expect(Validators.phone('12345'), isNotNull, reason: 'too short');
      expect(Validators.phone('call me'), isNotNull);
      expect(Validators.phone('+1 (555) 010-1234'), isNull);
      expect(Validators.phone('+8801712345678'), isNull);
      expect(Validators.phone('1234567890123456'), isNotNull, reason: 'too long');
    });

    test('password strength and confirmation', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('alllowercase1'), isNotNull);
      expect(Validators.password('NoDigitsHere'), isNotNull);
      expect(Validators.password('Admin@123'), isNull);
      expect(Validators.confirmPassword('Admin@123', 'Admin@124'), isNotNull);
      expect(Validators.confirmPassword('Admin@123', 'Admin@123'), isNull);
    });
  });

  group('Employee registration validation', () {
    final now = DateTime(2026, 11, 16);

    test('name and designation are required', () {
      expect(EmployeeValidators.name(''), isNotNull);
      expect(EmployeeValidators.name('  '), isNotNull);
      expect(EmployeeValidators.name('Amina Rahman'), isNull);
      expect(EmployeeValidators.designation(''), isNotNull);
      expect(EmployeeValidators.designation('Software Engineer'), isNull);
      expect(EmployeeValidators.designation('x' * 121), isNotNull);
    });

    test('date of birth must be a real past date', () {
      expect(EmployeeValidators.dateOfBirth(null, now: now), isNotNull);
      expect(EmployeeValidators.dateOfBirth(DateTime(2026, 11, 17), now: now), isNotNull);
      expect(EmployeeValidators.dateOfBirth(DateTime(1890, 1, 1), now: now), isNotNull);
      expect(EmployeeValidators.dateOfBirth(DateTime(1998, 5, 20), now: now), isNull);
    });
  });
}
