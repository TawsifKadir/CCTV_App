import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/json_box_store.dart';
import '../../data/local/local_database.dart';
import '../../data/models/activity.dart';
import '../../data/models/app_settings.dart';
import '../../data/remote/api_contracts.dart';
import '../../data/remote/demo_auth_api.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../constants/app_constants.dart';

/// App-wide (environment-independent) dependencies.
///
/// Backend-facing providers live with their features:
/// * environments: `features/environments/presentation/providers/`
/// * employees:    `features/employees/presentation/providers/`

/// Must be overridden in `main()` with the opened database.
final localDatabaseProvider = Provider<LocalDatabase>(
  (ref) => throw UnimplementedError('localDatabaseProvider must be overridden'),
);

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(localDatabaseProvider).box(BoxNames.settings)),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------------------------------------------------------------------------
// On-device activity log
// ---------------------------------------------------------------------------

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  final box = ref.watch(localDatabaseProvider).box(BoxNames.activities);
  return ActivityRepository(JsonBoxStore<Activity>(
    box: box,
    fromJson: Activity.fromJson,
    toJson: (a) => a.toJson(),
    keyOf: (a) => a.id,
  ));
});

class ActivitiesNotifier extends Notifier<List<Activity>> {
  @override
  List<Activity> build() {
    final repo = ref.watch(activityRepositoryProvider);
    final sub = repo.changes.listen((_) => state = repo.getAll());
    ref.onDispose(sub.cancel);
    return repo.getAll();
  }
}

final activitiesProvider = NotifierProvider<ActivitiesNotifier, List<Activity>>(ActivitiesNotifier.new);

// ---------------------------------------------------------------------------
// Operator authentication (demo, on-device — see DemoAuthApi)
// ---------------------------------------------------------------------------

final demoAuthApiProvider = Provider<DemoAuthApi>(
  (ref) => DemoAuthApi(ref.watch(localDatabaseProvider).box(BoxNames.demoOperators)),
);

/// Swap for an HTTP implementation when the backend offers authentication.
final authApiProvider = Provider<AuthApi>((ref) => ref.watch(demoAuthApiProvider));

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(authApiProvider),
    sessionBox: ref.watch(localDatabaseProvider).box(BoxNames.session),
    activity: ref.watch(activityRepositoryProvider),
  );
});

/// Value for the `Authorization` header of backend requests, or `null`.
/// The employee endpoints are unauthenticated today; return
/// `'Bearer <token>'` here once a real auth API issues tokens.
final authHeaderProvider = Provider<String? Function()>((ref) => () => null);
