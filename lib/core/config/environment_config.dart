/// A backend environment the app can talk to.
///
/// Instances are created only by `EnvironmentRegistry`; nothing else in the
/// app should construct base URLs.
class EnvironmentConfig {
  const EnvironmentConfig({
    required this.environmentId,
    required this.environmentName,
    required this.baseUrl,
    this.apiPrefix = '/api',
    this.isProduction = false,
    this.allowDebugFeatures = false,
    this.notes,
  });

  /// Stable identifier, e.g. `local`, `qa`. Matches `APP_ENV` and the
  /// Android flavor name. Used in cache keys and persisted preferences.
  final String environmentId;

  /// Human-readable name shown in the UI.
  final String environmentName;

  /// Server origin (scheme, host, port and optional context path), without
  /// the API prefix. `null` means the environment is not configured yet.
  final String? baseUrl;

  /// Path prefix shared by every API endpoint (the Spring controllers live
  /// under `/api`).
  final String apiPrefix;

  final bool isProduction;

  /// Enables developer conveniences such as request logging and the
  /// prominent environment banner.
  final bool allowDebugFeatures;

  /// Optional explanation shown in Settings (e.g. how localhost is mapped).
  final String? notes;

  bool get isConfigured => baseUrl != null && configurationError == null;

  /// `null` when the URL is usable; otherwise a message explaining why not.
  String? get configurationError {
    final url = baseUrl;
    if (url == null || url.trim().isEmpty) {
      return 'No backend URL is configured for "$environmentName".';
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'The backend URL for "$environmentName" is not a valid absolute URL: $url';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'The backend URL for "$environmentName" must use http or https: $url';
    }
    if (isProduction && uri.scheme != 'https') {
      return 'The production backend must use HTTPS: $url';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return 'The backend URL for "$environmentName" must not contain a query or fragment: $url';
    }
    return null;
  }

  /// Origin + optional context path, with no trailing slash.
  String get normalizedBaseUrl {
    final url = baseUrl?.trim();
    if (url == null || url.isEmpty) {
      throw StateError('Environment $environmentId has no base URL');
    }
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Base URL used by the HTTP client: `<baseUrl><apiPrefix>`.
  String get apiBaseUrl => '$normalizedBaseUrl${_normalizePath(apiPrefix)}';

  /// Resolves a server-provided URL (such as an employee `photoUrl`) against
  /// this environment.
  ///
  /// * Absolute URLs are returned unchanged.
  /// * Root-relative paths (`/api/employee/1/photo`) are appended to the base
  ///   URL. If the base URL has a context path that the server already
  ///   included, it is not duplicated.
  /// * Other relative paths are resolved against the base URL.
  String resolveUrl(String pathOrUrl) {
    final value = pathOrUrl.trim();
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return value;
    final base = normalizedBaseUrl;
    final basePath = Uri.parse(base).path; // '' or '/context'
    final path = value.startsWith('/') ? value : '/$value';
    if (basePath.isNotEmpty && basePath != '/' && path.startsWith('$basePath/')) {
      return '${Uri.parse(base).origin}$path';
    }
    return '$base$path';
  }

  static String _normalizePath(String p) {
    var s = p.trim();
    if (s.isEmpty || s == '/') return '';
    if (!s.startsWith('/')) s = '/$s';
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  EnvironmentConfig copyWith({String? baseUrl, String? notes}) => EnvironmentConfig(
    environmentId: environmentId,
    environmentName: environmentName,
    baseUrl: baseUrl ?? this.baseUrl,
    apiPrefix: apiPrefix,
    isProduction: isProduction,
    allowDebugFeatures: allowDebugFeatures,
    notes: notes ?? this.notes,
  );

  @override
  bool operator ==(Object other) =>
      other is EnvironmentConfig &&
      other.environmentId == environmentId &&
      other.baseUrl == baseUrl &&
      other.apiPrefix == apiPrefix;

  @override
  int get hashCode => Object.hash(environmentId, baseUrl, apiPrefix);

  @override
  String toString() => 'EnvironmentConfig($environmentId, $baseUrl)';
}
