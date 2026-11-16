import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../registration/domain/employee_photo.dart';
import '../../../registration/domain/employee_registration.dart';
import '../models/local_employee.dart';

/// Persistent store for employees registered on this device and their
/// photographs, scoped to one backend environment.
///
/// Storage: Hive — app-private files on Android/iOS, IndexedDB on the web —
/// so records and photos survive app restarts, device restarts and browser
/// refreshes. Records are JSON; photos are raw bytes in a lazy box (loaded
/// only when displayed or uploaded).
class LocalEmployeeRepository {
  LocalEmployeeRepository({
    required Box<dynamic> records,
    required LazyBox<dynamic> photos,
    required this.environmentId,
    DateTime Function()? clock,
  })  : _records = records,
        _photos = photos,
        _clock = clock ?? DateTime.now;

  final Box<dynamic> _records;
  final LazyBox<dynamic> _photos;
  final String environmentId;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  /// Emits whenever any local record changes.
  Stream<void> get changes => _records.watch().map((_) {});

  /// All records of this environment, newest first.
  List<LocalEmployee> all() {
    final out = <LocalEmployee>[];
    for (final raw in _records.values) {
      final e = _decode(raw);
      if (e != null && e.backendEnvironmentId == environmentId) out.add(e);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  LocalEmployee? get(String localId) {
    final e = _decode(_records.get(localId));
    return e != null && e.backendEnvironmentId == environmentId ? e : null;
  }

  /// Local record linked to a server employee id, if this device registered it.
  LocalEmployee? byServerId(int serverId) {
    for (final e in all()) {
      if (e.serverId == serverId) return e;
    }
    return null;
  }

  /// Saves a new registration and its photo. The photo is written first so a
  /// record never exists without its photograph.
  Future<LocalEmployee> create(
    EmployeeRegistration r, {
    required SyncStatus status,
    bool isTestData = false,
    String? localId,
  }) async {
    final now = _clock();
    final id = localId ?? newLocalId();
    final photoRef = 'photo_$id';
    await _photos.put(photoRef, r.photo.bytes);
    final e = LocalEmployee(
      localId: id,
      name: r.name.trim(),
      dateOfBirth: DateTime(r.dateOfBirth.year, r.dateOfBirth.month, r.dateOfBirth.day),
      designation: r.designation.trim(),
      localPhotoReference: photoRef,
      photoFormat: r.photo.format,
      photoOrigin: r.photo.origin,
      photoBytes: r.photo.sizeBytes,
      createdAt: now,
      updatedAt: now,
      syncStatus: status,
      backendEnvironmentId: environmentId,
      isTestData: isTestData,
    );
    await save(e);
    return e;
  }

  static String newLocalId() => _uuid.v4();

  Future<void> save(LocalEmployee e) => _records.put(e.localId, jsonEncode(e.toJson()));

  /// Applies [change] to the stored record and persists it.
  Future<LocalEmployee?> update(String localId, LocalEmployee Function(LocalEmployee) change) async {
    final current = get(localId);
    if (current == null) return null;
    final next = change(current).copyWith(updatedAt: _clock());
    await save(next);
    return next;
  }

  Future<Uint8List?> loadPhoto(String photoRef) async {
    final v = await _photos.get(photoRef);
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    return null;
  }

  /// Rebuilds the upload payload from the stored record and photo.
  Future<EmployeeRegistration?> registrationFor(LocalEmployee e) async {
    final bytes = await loadPhoto(e.localPhotoReference);
    if (bytes == null) return null;
    return EmployeeRegistration(
      name: e.name,
      dateOfBirth: e.dateOfBirth,
      designation: e.designation,
      photo: EmployeePhoto.fromBytes(bytes, origin: e.photoOrigin),
    );
  }

  /// Removes a record and its photo.
  Future<void> delete(String localId) async {
    final e = get(localId);
    if (e == null) return;
    await _records.delete(localId);
    await _photos.delete(e.localPhotoReference);
  }

  /// Deletes every record (and photo) of this environment.
  Future<int> clear() async {
    final items = all();
    for (final e in items) {
      await _records.delete(e.localId);
      await _photos.delete(e.localPhotoReference);
    }
    return items.length;
  }

  int get photoBytesTotal => all().fold(0, (s, e) => s + e.photoBytes);

  LocalEmployee? _decode(Object? raw) {
    if (raw is! String) return null;
    try {
      return LocalEmployee.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null; // a corrupted row must not break the app
    }
  }
}
