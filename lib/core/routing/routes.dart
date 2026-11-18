/// Route paths. Use these helpers instead of string literals.
class Routes {
  Routes._();

  static const login = '/login';
  static const home = '/home';
  static const employees = '/employees';
  static const enroll = '/enroll';
  static const enrollSuccess = '/enrolled';
  static const activity = '/activity';
  static const settings = '/settings';
  static const environment = '/environment';
  static const sync = '/sync';
  static const diagnostics = '/diagnostics';

  static String employee(String key) => '$employees/${Uri.encodeComponent(key)}';

  /// Routes that hide the mobile bottom bar (focused flows).
  static bool hidesBottomNav(String location) => location.startsWith(enroll) || location.startsWith(enrollSuccess);
}
