import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

import 'environment_config.dart';
import 'environment_registry.dart';

/// Compile-time settings, supplied with `--dart-define` (or
/// `--dart-define-from-file=config/<env>.json`).
class BuildDefines {
  BuildDefines._();

  /// Target environment id: local, development, qa, production, …
  static const appEnv = String.fromEnvironment('APP_ENV');

  /// Overrides the target environment's base URL for this build only.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Host for the `local` environment on physical devices (LAN IP).
  static const localApiHost = String.fromEnvironment('LOCAL_API_HOST');

  /// Lets non-production builds switch environments at runtime (Settings).
  static const allowEnvironmentSwitching = bool.fromEnvironment('ALLOW_ENV_SWITCHING', defaultValue: true);
}

/// How the build's environment was chosen.
enum EnvironmentSource {
  dartDefine('--dart-define=APP_ENV'),
  flavor('build flavor'),
  defaultLocal('default (no APP_ENV given)');

  const EnvironmentSource(this.label);
  final String label;
}

/// The environment a build was compiled for, and what it may switch to.
@immutable
class BuildEnvironment {
  const BuildEnvironment({
    required this.config,
    required this.source,
    required this.runtimeSwitchingAllowed,
    required this.available,
  });

  /// The environment the build targets.
  final EnvironmentConfig config;
  final EnvironmentSource source;

  /// `false` for production builds: they can never point at another server.
  final bool runtimeSwitchingAllowed;

  /// Configured environments the operator may select at runtime. Contains
  /// only [config] when switching is not allowed.
  final List<EnvironmentConfig> available;

  /// Registered but unconfigured environments (shown greyed out).
  List<EnvironmentConfig> unconfigured({PlatformInfo? platform}) => [
        for (final e in EnvironmentRegistry.all(platform: platform, localHostOverride: BuildDefines.localApiHost))
          if (!e.isConfigured) e,
      ];

  EnvironmentConfig? byId(String id) {
    for (final e in available) {
      if (e.environmentId == id) return e;
    }
    return null;
  }
}

/// Thrown at startup when the requested environment cannot be used. The app
/// shows this message instead of silently falling back to another server.
class EnvironmentConfigurationException implements Exception {
  const EnvironmentConfigurationException(this.environmentId, this.message);
  final String environmentId;
  final String message;

  @override
  String toString() => message;
}

/// Resolves the build environment from `APP_ENV`, then the build flavor,
/// then defaults to `local` (for plain `flutter run`).
///
/// All parameters exist for tests; the app calls this with no arguments.
BuildEnvironment resolveBuildEnvironment({
  String? appEnv,
  String? flavor,
  String? apiBaseUrlOverride,
  String? localHostOverride,
  bool? allowSwitching,
  PlatformInfo? platform,
}) {
  final pf = platform ?? PlatformInfo.current();
  final requestedEnv = (appEnv ?? BuildDefines.appEnv).trim();
  final requestedFlavor = (flavor ?? appFlavor ?? '').trim();
  final hostOverride = localHostOverride ?? BuildDefines.localApiHost;
  final urlOverride = (apiBaseUrlOverride ?? BuildDefines.apiBaseUrl).trim();

  final (String id, EnvironmentSource source) = requestedEnv.isNotEmpty
      ? (requestedEnv, EnvironmentSource.dartDefine)
      : requestedFlavor.isNotEmpty
          ? (requestedFlavor, EnvironmentSource.flavor)
          : ('local', EnvironmentSource.defaultLocal);

  final def = EnvironmentRegistry.definitionFor(id);
  if (def == null) {
    throw EnvironmentConfigurationException(
      id,
      'Unknown environment "$id" (from ${source.label}). '
      'Registered environments: ${EnvironmentRegistry.ids.join(', ')}.',
    );
  }

  var config = EnvironmentRegistry.configFor(def, platform: pf, localHostOverride: hostOverride);
  if (urlOverride.isNotEmpty) {
    config = config.copyWith(baseUrl: urlOverride, notes: 'Base URL set with API_BASE_URL for this build.');
  }
  final error = config.configurationError;
  if (error != null) {
    throw EnvironmentConfigurationException(
      def.id,
      '$error\n\nSet its baseUrl in lib/core/config/environment_registry.dart, '
      'or build with --dart-define=API_BASE_URL=<url>.',
    );
  }

  final switching = !config.isProduction && (allowSwitching ?? BuildDefines.allowEnvironmentSwitching);
  final available = switching
      ? [
          for (final e in EnvironmentRegistry.all(platform: pf, localHostOverride: hostOverride))
            if (e.environmentId == config.environmentId) config else if (e.isConfigured) e,
        ]
      : [config];

  return BuildEnvironment(
    config: config,
    source: source,
    runtimeSwitchingAllowed: switching,
    available: available,
  );
}
