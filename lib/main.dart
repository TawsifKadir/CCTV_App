import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_environment.dart';
import 'core/services/providers.dart';
import 'data/local/local_database.dart';
import 'features/authentication/providers/auth_controller.dart';
import 'features/environments/presentation/providers/environment_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve the backend environment first. An unknown or unconfigured
  // environment stops here with an explanation instead of silently falling
  // back to localhost or any other server.
  final BuildEnvironment environment;
  try {
    environment = resolveBuildEnvironment();
  } on EnvironmentConfigurationException catch (e) {
    runApp(ConfigurationErrorApp(error: e));
    return;
  }

  // Local storage for preferences, the operator session and the activity
  // log (app-private files on mobile, IndexedDB on the web).
  final db = await LocalDatabase.open();

  // Restore a remembered session (validated against the active
  // environment by AuthController).
  final bootstrap = ProviderContainer(overrides: [localDatabaseProvider.overrideWithValue(db)]);
  final session = await bootstrap.read(sessionStoreProvider).read();
  bootstrap.dispose();

  runApp(
    ProviderScope(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        initialSessionProvider.overrideWithValue(session),
        buildEnvironmentProvider.overrideWithValue(environment),
      ],
      child: const EnrollyApp(),
    ),
  );
}
