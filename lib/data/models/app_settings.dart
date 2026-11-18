import 'package:flutter/material.dart';

/// User-adjustable application preferences, persisted locally.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
    this.preferFrontCamera = true,
    this.selectedEnvironmentId,
    this.autoSync = true,
    this.syncOnWifiOnly = false,
    this.connectionCheckSeconds = 60,
  });

  /// Defaults to following the device's light/dark appearance.
  final ThemeMode themeMode;
  final bool reduceMotion;
  final bool preferFrontCamera;

  /// Runtime environment chosen in Settings (non-production builds only).
  final String? selectedEnvironmentId;

  /// Upload pending registrations automatically when the server is reachable.
  final bool autoSync;

  /// Restrict *automatic* synchronization to Wi-Fi/Ethernet. Manual "Sync
  /// now" always works on any connection.
  final bool syncOnWifiOnly;

  /// Seconds between backend reachability checks while online (admin builds
  /// can change it; client builds use the default).
  final int connectionCheckSeconds;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? reduceMotion,
    bool? preferFrontCamera,
    String? Function()? selectedEnvironmentId,
    bool? autoSync,
    bool? syncOnWifiOnly,
    int? connectionCheckSeconds,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    preferFrontCamera: preferFrontCamera ?? this.preferFrontCamera,
    selectedEnvironmentId: selectedEnvironmentId == null ? this.selectedEnvironmentId : selectedEnvironmentId(),
    autoSync: autoSync ?? this.autoSync,
    syncOnWifiOnly: syncOnWifiOnly ?? this.syncOnWifiOnly,
    connectionCheckSeconds: connectionCheckSeconds ?? this.connectionCheckSeconds,
  );

  // `themePreference` replaces the old `themeMode` key, whose default was
  // light: existing installs therefore start following the system theme.
  Map<String, dynamic> toJson() => {
    'themePreference': themeMode.name,
    'reduceMotion': reduceMotion,
    'preferFrontCamera': preferFrontCamera,
    'selectedEnvironmentId': selectedEnvironmentId,
    'autoSync': autoSync,
    'syncOnWifiOnly': syncOnWifiOnly,
    'connectionCheckSeconds': connectionCheckSeconds,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere((m) => m.name == j['themePreference'], orElse: () => d.themeMode),
      reduceMotion: j['reduceMotion'] as bool? ?? d.reduceMotion,
      preferFrontCamera: j['preferFrontCamera'] as bool? ?? d.preferFrontCamera,
      selectedEnvironmentId: j['selectedEnvironmentId'] as String?,
      autoSync: j['autoSync'] as bool? ?? d.autoSync,
      syncOnWifiOnly: j['syncOnWifiOnly'] as bool? ?? d.syncOnWifiOnly,
      connectionCheckSeconds: ((j['connectionCheckSeconds'] as num?)?.toInt() ?? d.connectionCheckSeconds).clamp(
        10,
        600,
      ),
    );
  }
}
