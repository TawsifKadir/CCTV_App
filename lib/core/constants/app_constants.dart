/// Application-wide constants: branding, storage keys, demo credentials.
///
/// Branding lives here so it can be swapped in a single place.
class AppConstants {
  AppConstants._();

  static const appName = 'Enrolly';
  static const tagline = 'Employee Enrollment & Identity Management';
  static const version = '2.0.0';

  /// Brand image (generated from assets/branding/source_photo.jpg).
  static const logoAsset = 'assets/branding/app_logo.png';

  /// Longest edge (px) of photos sent for registration. Large enough for
  /// face-template extraction, small enough to upload quickly.
  static const photoMaxEdge = 1600;
  static const photoJpegQuality = 90;

  /// Activity feed retention.
  static const maxActivities = 120;

  /// Sync history retention (runs).
  static const maxSyncHistory = 50;

  /// Search debounce for the employee list.
  static const searchDebounce = Duration(milliseconds: 400);
}

/// Hive box names. Keeping them together avoids typos and makes the storage
/// footprint easy to audit.
class BoxNames {
  BoxNames._();

  static const activities = 'activities';
  static const settings = 'settings';
  static const session = 'session';

  /// Offline-first employee data (per backend environment).
  static const localEmployees = 'local_employees';
  static const serverEmployeeCache = 'server_employee_cache';
  static const syncHistory = 'sync_history';

  /// Simulated server used only by demo sessions (non-production builds).
  static const demoBackend = 'demo_backend';

  /// Photographs of locally registered employees (lazy: loaded on demand,
  /// so large images are not all held in memory).
  static const localEmployeePhotos = 'local_employee_photos';

  static const all = [activities, settings, session, localEmployees, serverEmployeeCache, syncHistory, demoBackend];
  static const lazy = [localEmployeePhotos];

  /// Boxes from the previous offline customer/mock-sync model. They are
  /// deleted on startup so old customer photographs don't linger on disk.
  static const legacy = [
    'customers',
    'face_images',
    'sync_logs',
    'pending_deletions',
    'mock_backend_customers',
    'mock_backend_images',
    'mock_backend_meta',
    // Former on-device demo operator accounts (sign-in now uses the backend).
    'mock_backend_operators',
  ];
}
