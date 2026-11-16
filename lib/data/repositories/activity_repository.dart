import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../local/json_box_store.dart';
import '../models/activity.dart';

/// Append-only feed of notable events shown on the dashboard.
class ActivityRepository {
  ActivityRepository(this._store);

  final JsonBoxStore<Activity> _store;
  static const _uuid = Uuid();

  Stream<void> get changes => _store.changes;

  List<Activity> getAll() =>
      _store.getAll()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  Future<void> log(
    ActivityType type,
    String title, {
    String? subtitle,
    String? environmentId,
    DateTime? at,
  }) async {
    await _store.put(Activity(
      id: _uuid.v4(),
      type: type,
      title: title,
      subtitle: subtitle,
      timestamp: at ?? DateTime.now(),
      environmentId: environmentId,
    ));
    await _trim();
  }

  Future<void> _trim() async {
    if (_store.length <= AppConstants.maxActivities) return;
    final all = getAll();
    await _store.deleteAll(all.skip(AppConstants.maxActivities).map((a) => a.id));
  }

  Future<void> clear() => _store.clear();
}
