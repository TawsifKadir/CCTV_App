import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/motion.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_cards.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../providers/registration_controller.dart';

/// Shown after `POST /api/employee/add` returns 2xx. A registration whose
/// live watch-list update failed is still a success, shown with a warning.
class RegistrationSuccessScreen extends StatelessWidget {
  const RegistrationSuccessScreen({super.key, required this.outcome});

  final RegistrationOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final r = outcome.result;
    final e = r?.employee;
    final name = e?.name ?? outcome.submittedName;
    final onDevice = outcome.savedOnDeviceOnly;
    final delayed = r?.recognitionDelayed ?? false;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final color = onDevice ? AppColors.info : (delayed ? AppColors.warning : AppColors.success);

    final details = <Widget>[
      if (e?.employeeNo != null) _row(context, 'Employee number', Fmt.employeeNo(e!.employeeNo)),
      if (e?.id != null) _row(context, 'Employee ID', '${e!.id}'),
      if (e?.templateId != null) _row(context, 'Template ID', e!.templateId!, mono: true),
      if (onDevice) _row(context, 'Stored', 'On this device'),
      if (onDevice) _row(context, 'Status', outcome.record?.statusLabel ?? 'Sync pending'),
      if (!onDevice)
        _row(
          context,
          'Live recognition',
          switch (r!.liveWatchList) {
            true => 'Active',
            false => 'Pending',
            null => 'Not reported',
          },
        ),
    ];

    final Widget banner;
    if (onDevice) {
      banner = AppBanner(
        key: const Key('saved-locally-banner'),
        type: outcome.uncertain ? SnackType.warning : SnackType.info,
        title: 'Saved on this device',
        message: outcome.uncertain
            ? 'The server didn\'t confirm the registration. The employee is safe on this device, and the server '
                'will be checked before it is uploaded again.'
            : 'Employee saved on this device. Synchronization will resume when the server becomes available.',
      );
    } else if (delayed) {
      banner = AppBanner(
        key: const Key('watchlist-warning'),
        type: SnackType.warning,
        title: 'Recognition not active yet',
        message: r!.warningMessage,
      );
    } else {
      banner = const AppBanner(
        type: SnackType.success,
        message: 'The face template was created and the employee is in the live watch list.',
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  AnimatedCheckmark(size: 104, color: color),
                  const SizedBox(height: Space.md),
                  Text(onDevice ? 'Saved on this device' : 'Employee registered',
                          style: t.headlineMedium, textAlign: TextAlign.center)
                      .entrance(context, delay: const Duration(milliseconds: 350)),
                  const SizedBox(height: Space.xs),
                  Text(
                    onDevice
                        ? '$name is registered on this device and will be uploaded to the server automatically.'
                        : '$name has been saved to the server.',
                    style: t.bodyLarge?.copyWith(color: p.textMuted),
                    textAlign: TextAlign.center,
                  ).entrance(context, delay: const Duration(milliseconds: 420)),
                  const SizedBox(height: Space.lg),
                  AppCard(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.lg),
                          child: Image.memory(
                            outcome.photo.bytes,
                            width: 112,
                            height: 112,
                            fit: BoxFit.cover,
                            cacheWidth: (112 * dpr).round(),
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        Text(name, style: t.titleLarge, textAlign: TextAlign.center),
                        Text(e?.designation ?? outcome.designation, style: t.bodyMedium?.copyWith(color: p.textMuted)),
                        const SizedBox(height: Space.md),
                        ...details,
                        const SizedBox(height: Space.sm),
                        banner,
                      ],
                    ),
                  ).entrance(context, delay: const Duration(milliseconds: 500)),
                  const SizedBox(height: Space.lg),
                  AppPrimaryButton(
                    key: const Key('success-register-another'),
                    label: 'Register Another Employee',
                    icon: Icons.person_add_alt_outlined,
                    onPressed: () => context.go(Routes.enroll),
                  ),
                  const SizedBox(height: Space.sm),
                  AppSecondaryButton(
                    key: const Key('success-view-employees'),
                    label: onDevice ? 'View Pending Registrations' : 'View Employees',
                    icon: onDevice ? Icons.cloud_upload_outlined : Icons.people_alt_outlined,
                    onPressed: () => context.go(onDevice ? Routes.sync : Routes.employees),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool mono = false}) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: t.bodyMedium?.copyWith(color: context.palette.textMuted)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: mono ? t.bodySmall?.copyWith(fontFamily: 'monospace', color: context.palette.text) : t.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle-then-tick drawing animation with a soft halo. Paint-only: the
/// controller drives the painter's `repaint` listenable, so no widgets are
/// rebuilt per frame.
class AnimatedCheckmark extends StatefulWidget {
  const AnimatedCheckmark({super.key, this.size = 96, this.color = AppColors.success});

  final double size;
  final Color color;

  @override
  State<AnimatedCheckmark> createState() => _AnimatedCheckmarkState();
}

class _AnimatedCheckmarkState extends State<AnimatedCheckmark> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Success',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size * 1.5),
          painter: _CheckPainter(_c, widget.color),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.anim, this.color) : super(repaint: anim);
  final Animation<double> anim;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final center = size.center(Offset.zero);
    final r = size.width / 3; // circle radius (size is 1.5x the circle)
    final halo = Curves.easeOut.transform((t * 1.4).clamp(0, 1));
    canvas.drawCircle(center, r * (1 + 0.5 * halo), Paint()..color = color.withValues(alpha: 0.18 * (1 - halo * 0.6)));

    final circleT = Curves.easeOutBack.transform((t / 0.5).clamp(0, 1));
    canvas.drawCircle(center, r * circleT, Paint()..color = color);

    final checkT = Curves.easeOutCubic.transform(((t - 0.45) / 0.45).clamp(0, 1));
    if (checkT <= 0) return;
    final w = r * 2;
    final o = center - Offset(r, r);
    final path = Path()
      ..moveTo(o.dx + w * 0.29, o.dy + w * 0.52)
      ..lineTo(o.dx + w * 0.44, o.dy + w * 0.66)
      ..lineTo(o.dx + w * 0.72, o.dy + w * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * checkT),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.08
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color || old.anim != anim;
}
