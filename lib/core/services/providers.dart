import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/json_box_store.dart';
import '../../data/local/local_database.dart';
import '../../data/models/activity.dart';
import '../../data/models/app_settings.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../features/authentication/data/session_store.dart';
import '../../features/authentication/providers/auth_controller.dart';
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
  return ActivityRepository(
    JsonBoxStore<Activity>(box: box, fromJson: Activity.fromJson, toJson: (a) => a.toJson(), keyOf: (a) => a.id),
  );
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
// Operator authentication (POST /api/auth/login — see AuthController)
// ---------------------------------------------------------------------------

/// Secure storage for remembered sessions (overridden in tests).
final sessionStoreProvider = Provider<SessionStore>((ref) => SecureSessionStore());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    store: ref.watch(sessionStoreProvider),
    prefs: ref.watch(localDatabaseProvider).box(BoxNames.session),
    activity: ref.watch(activityRepositoryProvider),
  );
});

/// Authentication headers for every backend request (and photo downloads),
/// from the current session: `Authorization` when the login returned a
/// token, `Cookie` when it returned a server session cookie (native only —
/// browsers attach cookies themselves).
final authHeaderProvider = Provider<Map<String, String> Function()>(
  (ref) =>
      () => ref.read(authControllerProvider)?.requestHeaders ?? const {},
);
