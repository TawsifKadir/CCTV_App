import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._box);

  final Box<dynamic> _box;
  static const _key = 'app_settings';

  AppSettings load() {
    final raw = _box.get(_key);
    if (raw is! String) return const AppSettings();
    try {
      return AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) => _box.put(_key, jsonEncode(s.toJson()));
}
