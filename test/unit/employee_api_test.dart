import 'package:cctv_app/core/config/environment_config.dart';
import 'package:cctv_app/core/network/api_client.dart';
import 'package:cctv_app/core/network/api_exceptions.dart';
import 'package:cctv_app/features/employees/data/models/employee.dart';
import 'package:cctv_app/features/employees/data/models/employee_page.dart';
import 'package:cctv_app/features/employees/data/models/employee_query.dart';
import 'package:cctv_app/features/employees/data/repositories/employee_repository.dart';
import 'package:cctv_app/features/employees/data/services/employee_api_service.dart';
import 'package:cctv_app/features/registration/domain/employee_photo.dart';
import 'package:cctv_app/features/registration/domain/employee_registration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

const _local = EnvironmentConfig(environmentId: 'local', environmentName: 'Local', baseUrl: 'http://localhost:8080');

void main() {
  late FakeBackend backend;
  late EmployeeApiService api;

  EmployeeApiService serviceFor(EnvironmentConfig env) =>
      EmployeeApiService(ApiClient(environment: env, dio: Dio()..httpClientAdapter = backend));

  setUp(() {
    backend = FakeBackend();
    api = serviceFor(_local);
  });

  EmployeeRegistration registration({EmployeePhoto? photo, DateTime? dob}) => EmployeeRegistration(
    name: '  Amina Rahman ',
    dateOfBirth: dob ?? DateTime(1998, 5, 2),
    designation: 'Software Engineer',
    photo: photo ?? EmployeePhoto.fromBytes(fakeJpeg(), origin: PhotoOrigin.upload),
  );

  group('POST /api/employee/add', () {
    test('sends multipart/form-data with the exact EmployeeForm field names', () async {
      await api.registerEmployee(registration());
      final req = backend.last;
      expect(req.method, 'POST');
      expect(req.uri.toString(), 'http://localhost:8080/api/employee/add');
      expect(req.headers[Headers.contentTypeHeader].toString(), startsWith('multipart/form-data; boundary='));

      final form = req.data as FormData;
      expect(
        {for (final f in form.fields) f.key: f.value},
        {'name': 'Amina Rahman', 'dateOfBirth': '1998-05-02', 'designation': 'Software Engineer'},
      );
      expect(form.files.map((f) => f.key), ['photo']);
      expect(form.fields.map((f) => f.key), isNot(contains(anyOf('fullName', 'dob', 'image', 'employeePhoto'))));
    });

    test('dates are serialised as ISO YYYY-MM-DD', () {
      expect(isoDate(DateTime(1998, 5, 2)), '1998-05-02');
      expect(isoDate(DateTime(2001, 12, 31, 23, 59)), '2001-12-31');
      expect(isoDate(DateTime(987, 1, 9)), '0987-01-09');
    });

    test('the photo is a real file part with filename and image content type', () async {
      await api.registerEmployee(registration());
      final file = (backend.last.data as FormData).files.single.value;
      expect(file.filename, 'photo.jpg');
      expect(file.contentType.toString(), 'image/jpeg');
      expect(file.length, 2048);

      await api.registerEmployee(registration(photo: EmployeePhoto.fromBytes(fakePng(), origin: PhotoOrigin.camera)));
      final png = (backend.last.data as FormData).files.single.value;
      expect(png.filename, 'photo.png');
      expect(png.contentType.toString(), 'image/png');
    });

    test('HTTP 201 is parsed tolerantly into a successful result', () async {
      final r = await api.registerEmployee(registration());
      expect(r.statusCode, 201);
      expect(r.employee?.name, 'Example Employee');
      expect(r.employee?.employeeNo, 1001);
      expect(r.liveWatchList, isTrue);
      expect(r.recognitionDelayed, isFalse);
    });

    test('liveWatchList:false is still a successful registration, with its warning', () async {
      backend.handler = (_) => json(201, {
        'id': 7,
        'name': 'Amina Rahman',
        'liveWatchList': false,
        'warning': 'Employee saved. Recognition will be available when the engine starts.',
      });
      final r = await api.registerEmployee(registration());
      expect(r.statusCode, 201);
      expect(r.employee?.id, 7);
      expect(r.recognitionDelayed, isTrue);
      expect(r.warningMessage, 'Employee saved. Recognition will be available when the engine starts.');
    });

    test('an unexpected or empty 201 body does not fail the registration', () async {
      backend.handler = (_) => json(201, null);
      final empty = await api.registerEmployee(registration());
      expect(empty.employee, isNull);
      expect(empty.recognitionDelayed, isFalse);

      backend.handler = (_) => json(201, {
        'liveWatchList': 'false',
        'unknown': [1, 2],
      });
      final odd = await api.registerEmployee(registration());
      expect(odd.liveWatchList, isFalse);
    });

    test("shows the backend's own error message", () async {
      backend.handler = (_) => json(400, {'error': 'Enter a valid date of birth.'});
      await expectLater(
        api.registerEmployee(registration()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.message, 'message', 'Enter a valid date of birth.'),
        ),
      );
    });

    test('photos over 10 MB are rejected before any request is sent', () async {
      final big = fakeJpeg(10 * 1024 * 1024 + 1);
      expect(PhotoValidator.validate(big), contains('up to 10 MB'));
      expect(() => EmployeePhoto.fromBytes(big, origin: PhotoOrigin.upload), throwsA(isA<PhotoValidationException>()));
      expect(PhotoValidator.validate(fakeJpeg(10 * 1024 * 1024)), isNull, reason: 'exactly 10 MB is allowed');
      expect(backend.requests, isEmpty);
    });

    test('only JPEG and PNG are accepted (by file signature)', () {
      expect(PhotoValidator.detectFormat(fakeJpeg()), PhotoFormat.jpeg);
      expect(PhotoValidator.detectFormat(fakePng()), PhotoFormat.png);
      final gif = fakeJpeg()..setAll(0, 'GIF89a'.codeUnits);
      expect(PhotoValidator.validate(gif), 'Only JPEG and PNG photos are supported.');
      expect(PhotoValidator.validate(null), isNotNull);
    });

    test('invalid fields are rejected locally', () async {
      await expectLater(
        api.registerEmployee(registration(dob: DateTime.now().add(const Duration(days: 2)))),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.validation)),
      );
      expect(backend.requests, isEmpty);
    });
  });

  group('GET /api/employee/list', () {
    test('parses the paginated response into typed models', () async {
      backend.handler = (_) => json(200, {
        'content': [sampleEmployeeJson(photoUrl: '/api/employee/1/photo')],
        'page': 0,
        'size': 24,
        'totalElements': 100,
        'totalPages': 5,
        'hasPrevious': false,
        'hasNext': true,
      });
      final page = await api.getEmployees(const EmployeeQuery());
      expect(page.totalElements, 100);
      expect(page.totalPages, 5);
      expect(page.hasNext, isTrue);
      expect(page.hasPrevious, isFalse);
      final e = page.content.single;
      expect(e.id, 1);
      expect(e.employeeNo, 1001);
      expect(e.name, 'Example Employee');
      expect(e.dateOfBirth, DateTime(1998, 5, 20));
      expect(e.designation, 'Software Engineer');
      expect(e.templateId, 'template-1');
      expect(e.templateBytes, 2048);
      expect(e.enrolledAt, DateTime(2026, 11, 16, 10, 30));
      expect(e.photoUrl, '/api/employee/1/photo');
      expect(e.enrollmentSource, EnrollmentSource.photo);
    });

    test('sends page and size, and omits empty search and "all" source', () async {
      await api.getEmployees(const EmployeeQuery());
      final q = backend.last.uri.queryParameters;
      expect(backend.last.uri.path, '/api/employee/list');
      expect(q, {'page': '0', 'size': '24'});
    });

    test('pagination, search and source filter map to query parameters', () async {
      await api.getEmployees(
        const EmployeeQuery(page: 3, size: 24, query: '  Engineer ', source: EnrollmentSource.capture),
      );
      expect(backend.last.uri.queryParameters, {'page': '3', 'size': '24', 'query': 'Engineer', 'source': 'capture'});
      await api.getEmployees(const EmployeeQuery(source: EnrollmentSource.photo));
      expect(backend.last.uri.queryParameters['source'], 'photo');
    });

    test('never requests more than the backend maximum of 100', () async {
      await api.getEmployees(const EmployeeQuery(size: 500));
      expect(backend.last.uri.queryParameters['size'], '100');
    });

    test('tolerates nulls, string numbers and missing paging fields', () {
      final page = EmployeePage.fromJson({
        'content': [
          {'id': '5', 'name': null, 'employeeNo': null, 'photoUrl': '', 'enrollmentSource': 'cctv'},
        ],
        'totalElements': 30,
        'size': 24,
      });
      final e = page.content.single;
      expect(e.id, 5);
      expect(e.name, 'Unnamed employee');
      expect(e.hasPhoto, isFalse, reason: 'no photo is assumed when photoUrl is empty');
      expect(e.enrollmentSource, isNull);
      expect(e.sourceLabel, 'cctv');
      expect(page.totalPages, 2);
      expect(page.hasNext, isTrue);
    });

    test('invalid JSON and wrong shapes are reported, not crashed on', () async {
      backend.handler = (_) => text(200, '<html>oops</html>');
      await expectLater(
        api.getEmployees(const EmployeeQuery()),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.invalidResponse)),
      );

      backend.handler = (_) => json(200, null);
      await expectLater(
        api.getEmployees(const EmployeeQuery()),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.emptyResponse)),
      );

      backend.handler = (_) => json(200, [1, 2, 3]);
      await expectLater(
        api.getEmployees(const EmployeeQuery()),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.invalidResponse)),
      );
    });
  });

  group('error mapping', () {
    for (final (status, kind) in [
      (400, ApiErrorKind.badRequest),
      (401, ApiErrorKind.unauthorized),
      (403, ApiErrorKind.forbidden),
      (404, ApiErrorKind.notFound),
      (409, ApiErrorKind.conflict),
      (413, ApiErrorKind.payloadTooLarge),
      (422, ApiErrorKind.validation),
      (500, ApiErrorKind.server),
    ]) {
      test('HTTP $status → ${kind.name} with a friendly message', () async {
        backend.handler = (_) => text(status, '');
        await expectLater(
          api.getEmployees(const EmployeeQuery()),
          throwsA(
            isA<ApiException>()
                .having((e) => e.kind, 'kind', kind)
                .having((e) => e.message, 'message', isNot(contains('Exception'))),
          ),
        );
      });
    }

    test("Spring's default error document uses `message`, not the reason phrase", () {
      expect(
        ApiException.messageFromBody({'timestamp': 'x', 'status': 400, 'error': 'Bad Request', 'message': 'Bad size'}),
        'Bad size',
      );
      expect(ApiException.messageFromBody({'timestamp': 'x', 'status': 500, 'error': 'Internal Server Error'}), isNull);
      expect(
        ApiException.messageFromBody('{"error":"Upload a JPEG or PNG photo up to 10 MB."}'),
        'Upload a JPEG or PNG photo up to 10 MB.',
      );
      expect(ApiException.messageFromBody('<html>stack trace</html>'), isNull);
    });

    test('connection refused, DNS failures and timeouts are distinguished', () {
      DioException err(DioExceptionType type, [Object? error]) => DioException(
        requestOptions: RequestOptions(baseUrl: 'http://localhost:8080'),
        type: type,
        error: error,
      );
      expect(
        ApiException.fromDio(err(DioExceptionType.connectionError, 'SocketException: Connection refused')).kind,
        ApiErrorKind.connectionRefused,
      );
      expect(
        ApiException.fromDio(err(DioExceptionType.connectionError, 'Failed host lookup: qa.example')).kind,
        ApiErrorKind.dns,
      );
      expect(ApiException.fromDio(err(DioExceptionType.receiveTimeout)).kind, ApiErrorKind.timeout);
      expect(ApiException.fromDio(err(DioExceptionType.connectionTimeout)).kind, ApiErrorKind.timeout);
      final refused = ApiException.fromDio(err(DioExceptionType.connectionError, 'Connection refused'));
      expect(refused.message, contains('http://localhost:8080'));
      expect(refused.isNetwork, isTrue);
    });
  });

  group('photo URL resolution', () {
    test('relative photo URLs resolve against the active environment', () {
      expect(api.resolvePhotoUrl('/api/employee/1/photo'), 'http://localhost:8080/api/employee/1/photo');
      expect(api.resolvePhotoUrl('api/employee/1/photo'), 'http://localhost:8080/api/employee/1/photo');
      expect(api.resolvePhotoUrl(null), isNull);
      expect(api.resolvePhotoUrl('  '), isNull);
    });

    test('a different environment yields a different image source', () {
      final qa = serviceFor(
        const EnvironmentConfig(environmentId: 'qa', environmentName: 'QA', baseUrl: 'https://qa.example.com/'),
      );
      expect(qa.resolvePhotoUrl('/api/employee/1/photo'), 'https://qa.example.com/api/employee/1/photo');
    });

    test('absolute URLs are kept, context paths are not duplicated', () {
      expect(api.resolvePhotoUrl('https://cdn.example.com/p/1.jpg'), 'https://cdn.example.com/p/1.jpg');
      const ctx = EnvironmentConfig(environmentId: 'x', environmentName: 'X', baseUrl: 'https://h.example.com/enrolly');
      expect(ctx.resolveUrl('/api/employee/1/photo'), 'https://h.example.com/enrolly/api/employee/1/photo');
      expect(ctx.resolveUrl('/enrolly/api/employee/1/photo'), 'https://h.example.com/enrolly/api/employee/1/photo');
      expect(ctx.apiBaseUrl, 'https://h.example.com/enrolly/api');
    });
  });

  group('EmployeeRepository cache', () {
    test('serves repeat queries from cache and refetches after registration', () async {
      final repo = EmployeeRepository(api: api);
      await repo.getEmployees(const EmployeeQuery());
      await repo.getEmployees(const EmployeeQuery());
      expect(backend.listRequests, hasLength(1));

      await repo.getEmployees(const EmployeeQuery(page: 1));
      expect(backend.listRequests, hasLength(2), reason: 'different page, different key');

      await repo.registerEmployee(registration());
      await repo.getEmployees(const EmployeeQuery());
      expect(backend.listRequests, hasLength(3), reason: 'registration invalidates the cache');
    });

    test('cache keys include the environment id', () {
      final repo = EmployeeRepository(api: api);
      expect(repo.cacheKeyFor(const EmployeeQuery()), startsWith('local|'));
      final qaRepo = EmployeeRepository(
        api: serviceFor(
          const EnvironmentConfig(environmentId: 'qa', environmentName: 'QA', baseUrl: 'https://qa.example.com'),
        ),
      );
      expect(qaRepo.cacheKeyFor(const EmployeeQuery()), startsWith('qa|'));
      expect(qaRepo.cacheKeyFor(const EmployeeQuery()), isNot(repo.cacheKeyFor(const EmployeeQuery())));
    });

    test('entries expire after the TTL', () async {
      var now = DateTime(2026, 1, 1, 12);
      final repo = EmployeeRepository(api: api, clock: () => now);
      await repo.getEmployees(const EmployeeQuery());
      now = now.add(const Duration(seconds: 31));
      await repo.getEmployees(const EmployeeQuery());
      expect(backend.listRequests, hasLength(2));
    });
  });
}
