import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Brand-gradient surface with soft decorative rings and a faint dot grid.
/// Static paint only (no animation), isolated in a RepaintBoundary.
class BrandSurface extends StatelessWidget {
  const BrandSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.gradient = AppColors.brandGradient,
    this.dots = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Gradient gradient;
  final bool dots;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: borderRadius == BorderRadius.zero ? Clip.none : Clip.antiAlias,
        child: CustomPaint(
          painter: _DecorPainter(dots: dots),
          child: child,
        ),
      ),
    );
  }
}

class _DecorPainter extends CustomPainter {
  _DecorPainter({required this.dots});
  final bool dots;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.clipRect(Offset.zero & s);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.07);
    final r = s.shortestSide;
    canvas.drawCircle(Offset(s.width * 0.98, s.height * 0.02), r * 0.55, ring..strokeWidth = r * 0.08);
    canvas.drawCircle(Offset(s.width * 0.98, s.height * 0.02), r * 0.85, ring..strokeWidth = 1.2);
    canvas.drawCircle(
      Offset(s.width * 0.02, s.height * 1.02),
      r * 0.45,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
    if (dots) {
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.10);
      const gap = 16.0;
      final startX = s.width - gap * 7;
      for (var x = startX; x < s.width - gap; x += gap) {
        for (var y = s.height - gap * 5; y < s.height - gap; y += gap) {
          canvas.drawCircle(Offset(x, y), 1.4, dot);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DecorPainter old) => old.dots != dots;
}

/// Small numbered step marker ("1", "2") used to guide multi-part forms.
class StepBadge extends StatelessWidget {
  const StepBadge(this.number, {super.key});
  final int number;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: const BoxDecoration(gradient: AppColors.actionGradient, shape: BoxShape.circle),
    child: Text(
      '$number',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
    ),
  );
}
