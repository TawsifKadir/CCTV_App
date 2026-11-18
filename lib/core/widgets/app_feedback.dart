import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/motion.dart';
import 'app_buttons.dart';

/// Friendly, illustrated empty state.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final size = compact ? 72.0 : 112.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? Space.md : Space.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size * 1.35,
                    height: size * 1.35,
                    decoration: BoxDecoration(color: p.backgroundAlt.withValues(alpha: 0.6), shape: BoxShape.circle),
                  ),
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
                    child: Icon(icon, size: size * 0.42, color: AppColors.peach),
                  ),
                ],
              ),
              SizedBox(height: compact ? Space.md : Space.lg),
              Text(title, style: compact ? t.titleMedium : t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: Space.xs),
              Text(
                message,
                style: t.bodyMedium?.copyWith(color: p.textMuted),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Space.lg),
                AppPrimaryButton(label: actionLabel!, onPressed: onAction, expand: false, height: 48),
              ],
            ],
          ),
        ),
      ).entrance(context),
    );
  }
}

/// Branded loading spinner with optional message.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.message, this.size = 36});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(strokeWidth: 3, strokeCap: StrokeCap.round),
          ),
          if (message != null) ...[
            const SizedBox(height: Space.md),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Confirmation dialog. Returns `true` when confirmed.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
    ),
  );
  return result ?? false;
}

class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = destructive ? AppColors.error : AppColors.peach;
    return Dialog(
      insetPadding: const EdgeInsets.all(Space.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: Icon(
                  icon ?? (destructive ? Icons.delete_outline_rounded : Icons.help_outline_rounded),
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(height: Space.md),
              Text(title, style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: Space.xs),
              Text(
                message,
                style: t.bodyMedium?.copyWith(color: context.palette.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(
                    child: AppSecondaryButton(
                      label: cancelLabel,
                      height: 48,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: AppPrimaryButton(
                      label: confirmLabel,
                      height: 48,
                      color: color,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SnackType { info, success, error, warning }

/// Shows a floating, icon-led snackbar.
void showAppSnack(BuildContext context, String message, {SnackType type = SnackType.info}) {
  final (IconData icon, Color color) = switch (type) {
    SnackType.success => (Icons.check_circle_rounded, AppColors.success),
    SnackType.error => (Icons.error_rounded, AppColors.error),
    SnackType.warning => (Icons.warning_amber_rounded, AppColors.warning),
    SnackType.info => (Icons.info_rounded, AppColors.peachSoft),
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final width = MediaQuery.sizeOf(context).width;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: width > 600 ? 440 : null,
        duration: const Duration(seconds: 4),
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

/// Inline banner for errors / notices inside forms and pages.
class AppBanner extends StatelessWidget {
  const AppBanner({super.key, required this.message, this.type = SnackType.error, this.title, this.action});

  final String message;
  final String? title;
  final SnackType type;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (type) {
      SnackType.success => (Icons.check_circle_outline_rounded, AppColors.success),
      SnackType.error => (Icons.error_outline_rounded, AppColors.error),
      SnackType.warning => (Icons.warning_amber_rounded, AppColors.warning),
      SnackType.info => (Icons.info_outline_rounded, AppColors.info),
    };
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.md - 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: Radii.mdAll,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: t.labelLarge),
                Text(message, style: t.bodyMedium),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
