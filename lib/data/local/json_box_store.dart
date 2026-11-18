import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// Small typed wrapper around a Hive box whose values are JSON strings.
///
/// Reads are synchronous (Hive keeps opened boxes in memory); writes are
/// asynchronous and persisted to disk / IndexedDB.
class JsonBoxStore<T> {
  JsonBoxStore({required this.box, required this.fromJson, required this.toJson, required this.keyOf});

  final Box<dynamic> box;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;
  final String Function(T) keyOf;

  /// Emits whenever the underlying box changes.
  Stream<void> get changes => box.watch().map((_) {});

  List<T> getAll() {
    final out = <T>[];
    for (final raw in box.values) {
      final item = _decode(raw);
      if (item != null) out.add(item);
    }
    return out;
  }

  T? get(String key) => _decode(box.get(key));

  bool containsKey(String key) => box.containsKey(key);

  int get length => box.length;

  Future<void> put(T item) => box.put(keyOf(item), jsonEncode(toJson(item)));

  Future<void> putAll(Iterable<T> items) => box.putAll({for (final i in items) keyOf(i): jsonEncode(toJson(i))});

  Future<void> delete(String key) => box.delete(key);

  Future<void> deleteAll(Iterable<String> keys) => box.deleteAll(keys);

  Future<void> clear() => box.clear();

  /// Corrupted entries are skipped rather than crashing the UI.
  T? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      return fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }
}
