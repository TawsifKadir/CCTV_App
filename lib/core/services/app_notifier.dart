import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../widgets/app_feedback.dart';
import '../theme/app_colors.dart';

/// Messenger for notifications raised outside widgets (connectivity and
/// synchronization events). Wired into MaterialApp.scaffoldMessengerKey.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows subtle toasts without repeating the same message.
class AppNotifier {
  AppNotifier({GlobalKey<ScaffoldMessengerState>? key, this.dedupeWindow = const Duration(seconds: 20)})
    : _key = key ?? appMessengerKey;

  final GlobalKey<ScaffoldMessengerState> _key;
  final Duration dedupeWindow;
  String? _lastMessage;
  DateTime? _lastAt;

  /// Every message shown (for tests/diagnostics).
  final shown = <String>[];

  void show(String message, {SnackType type = SnackType.info, String? actionLabel, VoidCallback? onAction}) {
    final now = DateTime.now();
    if (message == _lastMessage && _lastAt != null && now.difference(_lastAt!) < dedupeWindow) return;
    _lastMessage = message;
    _lastAt = now;
    shown.add(message);
    final messenger = _key.currentState;
    if (messenger == null) return;
    final (IconData icon, Color color) = switch (type) {
      SnackType.success => (Icons.check_circle_rounded, AppColors.success),
      SnackType.error => (Icons.error_rounded, AppColors.error),
      SnackType.warning => (Icons.warning_amber_rounded, AppColors.warning),
      SnackType.info => (Icons.info_rounded, AppColors.peachSoft),
    };
    final width = MediaQuery.maybeSizeOf(messenger.context)?.width ?? 0;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          width: width > 600 ? 460 : null,
          duration: Duration(seconds: actionLabel == null ? 4 : 7),
          action: actionLabel == null
              ? null
              : SnackBarAction(label: actionLabel, textColor: AppColors.peach, onPressed: onAction ?? () {}),
          content: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: Space.sm),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}
