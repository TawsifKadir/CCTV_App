import 'package:flutter/foundation.dart';

import 'environment_config.dart';

/// Where the running app is, for resolving "localhost" correctly.
@immutable
class PlatformInfo {
  const PlatformInfo({required this.isWeb, required this.platform});

  /// The platform this code is running on.
  factory PlatformInfo.current() => PlatformInfo(isWeb: kIsWeb, platform: defaultTargetPlatform);

  final bool isWeb;
  final TargetPlatform platform;

  bool get isAndroid => !isWeb && platform == TargetPlatform.android;
}

/// Static description of one backend environment. See [EnvironmentRegistry].
@immutable
class EnvironmentDefinition {
  const EnvironmentDefinition({
    required this.id,
    required this.name,
    this.baseUrl,
    this.localPort,
    this.apiPrefix = '/api',
    this.isProduction = false,
    this.allowDebugFeatures = false,
  }) : assert(baseUrl == null || localPort == null, 'Use either baseUrl or localPort');

  final String id;
  final String name;

  /// Fixed server origin, e.g. `https://qa-api.example.com`. `null` = not
  /// configured yet.
  final String? baseUrl;

  /// For a backend on the developer's machine: the port it listens on. The
  /// host is chosen per platform (see [EnvironmentRegistry.localHostFor]).
  final int? localPort;

  final String apiPrefix;
  final bool isProduction;
  final bool allowDebugFeatures;
}

/// ============================================================================
///  BACKEND ENVIRONMENT REGISTRY — the single place to add or change URLs.
/// ============================================================================
///
/// To configure an environment, set its `baseUrl` below, for example:
///
///     EnvironmentDefinition(id: 'qa', name: 'QA', baseUrl: 'https://qa-api.example.com'),
///
/// To add a new environment, append another [EnvironmentDefinition] with a
/// unique `id`. Nothing else needs to change: API services, image URLs and
/// the Settings screen all read from here. (For a matching Android build,
/// also add a product flavor with the same name in
/// `android/app/build.gradle.kts`.)
///
/// A single build can also be pointed at another server without editing
/// this file: `--dart-define=API_BASE_URL=https://host:port`.
class EnvironmentRegistry {
  EnvironmentRegistry._();

  static const definitions = <EnvironmentDefinition>[
    // Spring Boot backend running on the developer's machine.
    EnvironmentDefinition(id: 'local', name: 'Local', localPort: 8080, allowDebugFeatures: true),
    // Live development server. Plain HTTP: traffic (including employee
    // photos) is unencrypted — move to HTTPS before real use.
    EnvironmentDefinition(
      id: 'development',
      name: 'Development',
      baseUrl: 'http://27.147.174.107:8085',
      allowDebugFeatures: true,
    ),
    // UNCONFIGURED — set baseUrl when the QA server URL is known.
    EnvironmentDefinition(id: 'qa', name: 'QA', baseUrl: null),
    // UNCONFIGURED — set baseUrl (HTTPS only) when the production URL is known.
    EnvironmentDefinition(id: 'production', name: 'Production', baseUrl: null, isProduction: true),
  ];

  /// Host used to reach the developer machine from a local build.
  ///
  /// * Web and iOS simulator: `localhost`.
  /// * Android emulator: `10.0.2.2` (the emulator's alias for the host).
  /// * Physical phones/tablets: pass the computer's LAN address with
  ///   `--dart-define=LOCAL_API_HOST=192.168.1.20`.
  static String localHostFor(PlatformInfo platform, {String hostOverride = ''}) {
    if (hostOverride.trim().isNotEmpty) return hostOverride.trim();
    if (platform.isAndroid) return '10.0.2.2';
    return 'localhost';
  }

  static String? _localNotes(PlatformInfo platform, String hostOverride) {
    if (hostOverride.trim().isNotEmpty) return 'Host set with LOCAL_API_HOST.';
    if (platform.isAndroid) {
      return 'Android emulator maps the host machine to 10.0.2.2. On a physical '
          'device, rebuild with --dart-define=LOCAL_API_HOST=<your computer\'s LAN IP>.';
    }
    if (!platform.isWeb && platform.platform == TargetPlatform.iOS) {
      return 'The iOS simulator shares the host network. On a physical device, rebuild '
          'with --dart-define=LOCAL_API_HOST=<your computer\'s LAN IP>.';
    }
    return null;
  }

  /// Builds the config for [d] on [platform].
  static EnvironmentConfig configFor(EnvironmentDefinition d, {PlatformInfo? platform, String localHostOverride = ''}) {
    final pf = platform ?? PlatformInfo.current();
    String? url = d.baseUrl;
    String? notes;
    if (d.localPort != null) {
      url = 'http://${localHostFor(pf, hostOverride: localHostOverride)}:${d.localPort}';
      notes = _localNotes(pf, localHostOverride);
    }
    return EnvironmentConfig(
      environmentId: d.id,
      environmentName: d.name,
      baseUrl: url,
      apiPrefix: d.apiPrefix,
      isProduction: d.isProduction,
      allowDebugFeatures: d.allowDebugFeatures,
      notes: notes,
    );
  }

  /// Every registered environment (configured or not).
  static List<EnvironmentConfig> all({PlatformInfo? platform, String localHostOverride = ''}) => [
    for (final d in definitions) configFor(d, platform: platform, localHostOverride: localHostOverride),
  ];

  static EnvironmentDefinition? definitionFor(String id) {
    final key = id.trim().toLowerCase();
    for (final d in definitions) {
      if (d.id == key) return d;
    }
    return null;
  }

  static List<String> get ids => [for (final d in definitions) d.id];
}
