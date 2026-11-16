import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

import 'app_environment.dart';

/// `true` when the build was *compiled* for production (APP_ENV, or the
/// production flavor when APP_ENV is absent). Because it is a compile-time
/// constant, admin-only code guarded by it is removed from production
/// binaries by the compiler, not merely hidden.
const bool kProductionBuild =
    BuildDefines.appEnv == 'production' || (BuildDefines.appEnv == '' && appFlavor == 'production');

/// Which product experience a build gets, decided at build time.
///
/// * **Client mode**: production builds. A clean operational UI:
///   dashboard, employees, registration, synchronization and client
///   settings. No backend URLs, environment switching, network inspection,
///   database inspection, test data or debug controls.
/// * **Admin mode**: local, development and QA builds. Everything in client
///   mode plus diagnostics and configuration.
///
/// Admin features are excluded at *registration* level: their routes are
/// never added to the router, the request recorder is never installed in
/// the HTTP client, and their providers are never read. Hiding a menu item
/// is not the protection.
///
/// `--dart-define=CLIENT_MODE=true` previews client mode on a non-production
/// build (e.g. to test the client UI against the development server). There
/// is deliberately no way to turn admin mode on in a production build.
@immutable
class AppFeatures {
  const AppFeatures({required this.clientMode});

  static const _forceClientMode = bool.fromEnvironment('CLIENT_MODE');

  factory AppFeatures.forBuild(BuildEnvironment build, {bool? forceClientMode}) =>
      AppFeatures(clientMode: build.config.isProduction || (forceClientMode ?? _forceClientMode));

  final bool clientMode;
  bool get adminMode => !kProductionBuild && !clientMode;

  // Admin-only capabilities.
  bool get environmentConfiguration => adminMode;
  bool get environmentIndicator => adminMode;
  bool get networkInspector => adminMode;
  bool get syncDiagnostics => adminMode;
  bool get databaseInspector => adminMode;
  bool get testDataTools => adminMode;
  bool get connectionIntervalSetting => adminMode;
  bool get rawRecordDetails => adminMode;
  bool get activityLog => adminMode;
}
