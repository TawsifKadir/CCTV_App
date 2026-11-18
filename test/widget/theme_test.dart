import 'dart:io';

import 'package:cctv_app/app.dart';
import 'package:cctv_app/core/services/providers.dart';
import 'package:cctv_app/core/theme/app_colors.dart';
import 'package:cctv_app/core/theme/app_theme.dart';
import 'package:cctv_app/data/local/local_database.dart';
import 'package:cctv_app/data/models/app_settings.dart';
import 'package:cctv_app/features/authentication/providers/auth_controller.dart';
import 'package:cctv_app/features/environments/presentation/providers/environment_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_env.dart';

void main() {
  late Directory dir;
  late LocalDatabase db;

  setUpAll(() async {
    AppTheme.useGoogleFonts = false;
    dir = await Directory.systemTemp.createTemp('enrolly_theme_');
    db = await LocalDatabase.open(path: dir.path);
    final c = ProviderContainer(overrides: [localDatabaseProvider.overrideWithValue(db)]);
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(reduceMotion: true));
    c.dispose();
  });

  tearDownAll(() async {
    // Writes issued inside testWidgets' fake-async zone can leave Hive's
    // write queue pending forever, so don't wait indefinitely on close.
    await Future.any([db.close(), Future<void>.delayed(const Duration(seconds: 2))]);
    await dir.delete(recursive: true).catchError((_) => dir);
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        initialSessionProvider.overrideWithValue(null),
        buildEnvironmentProvider.overrideWithValue(testBuildEnvironment()),
        dioFactoryProvider.overrideWithValue(() => Dio()..httpClientAdapter = FakeBackend()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EnrollyApp()));
    await tester.pumpAndSettle();
    return container;
  }

  Brightness brightness(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
  Color background(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).first)).extension<AppPalette>()!.background;

  void setSystem(WidgetTester tester, Brightness b) {
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  void setMode(ProviderContainer c, ThemeMode m) =>
      c.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: m));

  test('System default is the default preference', () {
    expect(const AppSettings().themeMode, ThemeMode.system);
    expect(AppSettings.fromJson(const {}).themeMode, ThemeMode.system);
    expect(
      AppSettings.fromJson(const {'themeMode': 'light'}).themeMode,
      ThemeMode.system,
      reason: 'the legacy light default is not carried over',
    );
  });

  testWidgets('follows a light system appearance', (tester) async {
    setSystem(tester, Brightness.light);
    final c = await pump(tester);
    setMode(c, ThemeMode.system);
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light);
    expect(background(tester), AppPalette.light.background);
  });

  testWidgets('follows a dark system appearance and updates live when it changes', (tester) async {
    setSystem(tester, Brightness.dark);
    final c = await pump(tester);
    setMode(c, ThemeMode.system);
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.dark);
    expect(background(tester), AppPalette.dark.background);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light, reason: 'no restart needed');
  });

  testWidgets('manual Light and Dark override the system until System is chosen again', (tester) async {
    setSystem(tester, Brightness.dark);
    final c = await pump(tester);

    setMode(c, ThemeMode.light);
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light);

    setSystem(tester, Brightness.light);
    setMode(c, ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.dark);

    setMode(c, ThemeMode.system);
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light, reason: 'back to following the device');
  });

  test('dark theme is a distinct palette, not an inversion', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(dark.colorScheme.primary, light.colorScheme.primary, reason: 'same peach identity');
    expect(dark.scaffoldBackgroundColor, isNot(light.scaffoldBackgroundColor));
    expect(dark.scaffoldBackgroundColor.computeLuminance(), lessThan(0.05));
    expect(dark.colorScheme.onSurface.computeLuminance(), greaterThan(0.7));
  });
}
