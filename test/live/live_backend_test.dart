// Live smoke test against a real backend, using the app's own HTTP client,
// service, models and error mapping. Skipped unless a URL is given:
//
//   flutter test test/live --dart-define=LIVE_API_BASE_URL=http://27.147.174.107:8085
//
// It is SAFE for live servers: it only lists employees and sends
// registrations that the backend rejects before saving anything (invalid
// date / missing photo). It never creates an employee.
import 'package:cctv_app/core/config/api_endpoints.dart';
import 'package:cctv_app/core/config/environment_config.dart';
import 'package:cctv_app/core/network/api_client.dart';
import 'package:cctv_app/core/network/api_exceptions.dart';
import 'package:cctv_app/features/employees/data/models/employee.dart';
import 'package:cctv_app/features/employees/data/models/employee_query.dart';
import 'package:cctv_app/features/employees/data/services/employee_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('LIVE_API_BASE_URL');

void main() {
  final skip = _baseUrl.isEmpty ? 'Set --dart-define=LIVE_API_BASE_URL=<url> to run' : null;
  const env = EnvironmentConfig(environmentId: 'live', environmentName: 'Live', baseUrl: _baseUrl == '' ? null : _baseUrl);
  late ApiClient client;
  late EmployeeApiService api;

  setUp(() {
    client = ApiClient(environment: env);
    api = EmployeeApiService(client);
  });
  tearDown(() => client.close());

  group('live backend $_baseUrl', skip: skip, () {
    test('list endpoint parses into a typed page', () async {
      final page = await api.getEmployees(const EmployeeQuery());
      expect(page.page, 0);
      expect(page.size, ApiEndpoints.defaultPageSize);
      expect(page.totalElements, greaterThanOrEqualTo(0));
      expect(page.content.length, lessThanOrEqualTo(page.size));
      expect(page.hasPrevious, isFalse);
      // ignore: avoid_print
      print('live: ${page.totalElements} employees, ${page.totalPages} pages');
      for (final e in page.content) {
        expect(e.name, isNotEmpty);
        if (e.hasPhoto) expect(api.resolvePhotoUrl(e.photoUrl), startsWith(_baseUrl));
      }
    });

    test('search, source filters and size cap are accepted', () async {
      for (final q in const [
        EmployeeQuery(query: 'engineer'),
        EmployeeQuery(source: EnrollmentSource.photo),
        EmployeeQuery(source: EnrollmentSource.capture),
        EmployeeQuery(size: 500),
      ]) {
        final page = await api.getEmployees(q);
        expect(page.size, lessThanOrEqualTo(ApiEndpoints.maxPageSize));
        if (q.source != null) {
          expect(page.content.every((e) => e.enrollmentSource == q.source), isTrue);
        }
      }
    });

    test("an invalid date is rejected with the backend's message (nothing saved)", () async {
      final form = FormData.fromMap({
        'name': 'Live smoke test',
        'dateOfBirth': '20-05-1998',
        'designation': 'Test',
        'photo': MultipartFile.fromString('x', filename: 'photo.jpg'),
      });
      await expectLater(
        client.postMultipart(ApiEndpoints.employeeAdd, form),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.message, 'message', 'Enter a valid date of birth.')),
      );
    });

    test("a missing photo is rejected with the backend's message (nothing saved)", () async {
      final form = FormData.fromMap({'name': 'Live smoke test', 'dateOfBirth': '1998-05-20', 'designation': 'Test'});
      await expectLater(
        client.postMultipart(ApiEndpoints.employeeAdd, form),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Upload a JPEG or PNG photo up to 10 MB.')),
      );
    });

    test('a missing photo id maps to not-found', () async {
      await expectLater(
        client.get('/employee/999999999/photo'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.notFound)),
      );
    });
  });
}
