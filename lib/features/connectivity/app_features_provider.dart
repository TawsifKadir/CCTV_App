import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_features.dart';
import '../environments/presentation/providers/environment_providers.dart';

/// Feature set of this build (client vs admin mode). Derived from the build
/// environment, which is fixed at build time.
final appFeaturesProvider = Provider<AppFeatures>((ref) => AppFeatures.forBuild(ref.watch(buildEnvironmentProvider)));
