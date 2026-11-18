import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// Brand mark: the supplied branding photograph (the same image as the
/// launcher icon) in a rounded tile. Falls back to a vector mark if the
/// asset cannot be loaded. Change [AppConstants.logoAsset] to rebrand.
class EnrollyLogoMark extends StatelessWidget {
  const EnrollyLogoMark({super.key, this.size = 44, this.background = AppColors.primary});

  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    return Semantics(
      label: '${AppConstants.appName} logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: background.withValues(alpha: 0.3), blurRadius: size * 0.3, offset: Offset(0, size * 0.1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Image.asset(
            AppConstants.logoAsset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            // Decode at display size rather than the full 256 px asset.
            cacheWidth: (size * dpr).round(),
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => CustomPaint(painter: _MarkPainter()),
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;
    final inset = w * 0.22;
    final len = w * 0.15;
    // Corner brackets.
    final corners = [
      [Offset(inset, inset + len), Offset(inset, inset), Offset(inset + len, inset)],
      [Offset(w - inset - len, inset), Offset(w - inset, inset), Offset(w - inset, inset + len)],
      [Offset(inset, w - inset - len), Offset(inset, w - inset), Offset(inset + len, w - inset)],
      [Offset(w - inset - len, w - inset), Offset(w - inset, w - inset), Offset(w - inset, w - inset - len)],
    ];
    for (final c in corners) {
      canvas.drawPath(
        Path()
          ..moveTo(c[0].dx, c[0].dy)
          ..lineTo(c[1].dx, c[1].dy)
          ..lineTo(c[2].dx, c[2].dy),
        stroke,
      );
    }
    final fill = Paint()..color = Colors.white;
    // Head.
    canvas.drawCircle(Offset(w / 2, w * 0.43), w * 0.095, fill);
    // Shoulders.
    final shoulders = Rect.fromCenter(center: Offset(w / 2, w * 0.70), width: w * 0.36, height: w * 0.26);
    canvas.drawArc(shoulders, 3.14159, 3.14159, true, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Logo mark + wordmark.
class EnrollyLogo extends StatelessWidget {
  const EnrollyLogo({super.key, this.size = 40, this.light = false, this.showTagline = false});

  final double size;
  final bool light;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = light ? AppColors.white : context.palette.text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EnrollyLogoMark(size: size),
        SizedBox(width: size * 0.3),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConstants.appName,
                style: t.titleLarge?.copyWith(color: color, fontSize: size * 0.5, height: 1.1),
              ),
              if (showTagline)
                Text(AppConstants.tagline, style: t.bodySmall?.copyWith(color: light ? Colors.white70 : null)),
            ],
          ),
        ),
      ],
    );
  }
}
