/// API paths, relative to `EnvironmentConfig.apiBaseUrl` (which already
/// includes the `/api` prefix).
class ApiEndpoints {
  ApiEndpoints._();

  /// POST multipart/form-data: name, dateOfBirth, designation, photo.
  static const employeeAdd = '/employee/add';

  /// GET ?page=&size=&query=&source=
  static const employeeList = '/employee/list';

  /// Backend limits for the list endpoint.
  static const defaultPageSize = 24;
  static const maxPageSize = 100;

  /// Backend limit for the `photo` part (EmployeeForm.photoBytes()).
  static const maxPhotoBytes = 10 * 1024 * 1024;
}
