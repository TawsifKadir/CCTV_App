import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum ActivityType {
  employeeRegistered(Icons.person_add_alt_1_rounded, AppColors.peach),
  recognitionPending(Icons.hourglass_top_rounded, AppColors.warning),
  registrationFailed(Icons.error_outline_rounded, AppColors.error),
  environmentChanged(Icons.dns_outlined, AppColors.info),
  login(Icons.login_rounded, AppColors.muted),
  registered(Icons.badge_outlined, AppColors.peach),
  system(Icons.settings_suggest_outlined, AppColors.muted);

  const ActivityType(this.icon, this.color);
  final IconData icon;
  final Color color;

  static ActivityType fromName(String? n) =>
      ActivityType.values.firstWhere((t) => t.name == n, orElse: () => ActivityType.system);
}

/// A line in the on-device activity feed (what this operator did here).
/// It is a local log, not backend data.
@immutable
class Activity {
  const Activity({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    required this.timestamp,
    this.environmentId,
  });

  final String id;
  final ActivityType type;
  final String title;
  final String? subtitle;
  final DateTime timestamp;

  /// Backend environment the event relates to, if any.
  final String? environmentId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'subtitle': subtitle,
    'timestamp': timestamp.toIso8601String(),
    'environmentId': environmentId,
  };

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
    id: j['id'] as String,
    type: ActivityType.fromName(j['type'] as String?),
    title: j['title'] as String? ?? '',
    subtitle: j['subtitle'] as String?,
    timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    environmentId: j['environmentId'] as String?,
  );
}
