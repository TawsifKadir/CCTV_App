import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../core/constants/app_constants.dart';

/// Opens the persistent Hive boxes used by the app.
///
/// Hive works on every target platform:
/// * Android / iOS: binary files inside the application documents
///   directory (application-managed, private storage).
/// * Web: the browser's IndexedDB.
///
/// Values are stored as JSON strings (and photo bytes), so no code generation
/// or type adapters are needed. Employees registered on this device are
/// stored here until (and after) they reach the backend; see
/// LocalEmployeeRepository.
class LocalDatabase {
  LocalDatabase._(this._boxes, this._lazyBoxes);

  final Map<String, Box<dynamic>> _boxes;
  final Map<String, LazyBox<dynamic>> _lazyBoxes;

  /// Initialises Hive. Pass [path] to use a plain directory (unit tests);
  /// otherwise Flutter's platform storage location is used.
  static Future<LocalDatabase> open({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter('enrolly');
    }
    for (final name in BoxNames.legacy) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {
        // Best effort: a missing legacy box is the normal case.
      }
    }
    final boxes = <String, Box<dynamic>>{};
    for (final name in BoxNames.all) {
      boxes[name] = await _openSafely(name);
    }
    final lazy = <String, LazyBox<dynamic>>{};
    for (final name in BoxNames.lazy) {
      try {
        lazy[name] = await Hive.openLazyBox<dynamic>(name);
      } catch (_) {
        await Hive.deleteBoxFromDisk(name);
        lazy[name] = await Hive.openLazyBox<dynamic>(name);
      }
    }
    return LocalDatabase._(boxes, lazy);
  }

  /// Opens a box; if its file is corrupted, deletes and recreates it rather
  /// than leaving the app unable to start.
  static Future<Box<dynamic>> _openSafely(String name) async {
    try {
      return await Hive.openBox<dynamic>(name);
    } catch (_) {
      await Hive.deleteBoxFromDisk(name);
      return Hive.openBox<dynamic>(name);
    }
  }

  Box<dynamic> box(String name) {
    final b = _boxes[name];
    if (b == null) throw StateError('Box $name is not open');
    return b;
  }

  LazyBox<dynamic> lazyBox(String name) {
    final b = _lazyBoxes[name];
    if (b == null) throw StateError('Lazy box $name is not open');
    return b;
  }

  Future<void> close() => Hive.close();
}
