import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/motion.dart';

/// Overlay that dims everything outside an oval face guide and draws a
/// gently breathing outline with corner brackets.
///
/// Performance: the static dim layer and the animated outline are separate
/// painters behind a [RepaintBoundary], so each frame repaints only the thin
/// outline (not the dim overlay, and never the camera texture beneath).
/// The dim shape uses an even-odd path instead of a per-frame
/// `Path.combine`, and the animation drives the painter's `repaint`
/// listenable directly — no widget rebuilds while it runs.
class CameraCaptureFrame extends StatefulWidget {
  const CameraCaptureFrame({super.key, this.active = true, this.success = false});

  /// Animate the guide and dim the surroundings (false while reviewing).
  final bool active;

  /// Draw the guide in the success colour.
  final bool success;

  @override
  State<CameraCaptureFrame> createState() => _CameraCaptureFrameState();
}

class _CameraCaptureFrameState extends State<CameraCaptureFrame> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final _t = CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CameraCaptureFrame old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && !context.reduceMotion) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.success ? AppColors.success : AppColors.peach;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.active) const CustomPaint(painter: _DimPainter()),
          RepaintBoundary(
            child: CustomPaint(painter: _OutlinePainter(_t, color)),
          ),
        ],
      ),
    );
  }
}

Rect _ovalFor(Size size) {
  final w = size.width, h = size.height;
  final ovalW = w * 0.62;
  final ovalH = ovalW * 1.3 > h * 0.78 ? h * 0.78 : ovalW * 1.3;
  return Rect.fromCenter(center: Offset(w / 2, h * 0.47), width: ovalW, height: ovalH);
}

class _DimPainter extends CustomPainter {
  const _DimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(_ovalFor(size));
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.38));
  }

  @override
  bool shouldRepaint(_DimPainter old) => false;
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.t, this.color) : super(repaint: t);
  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final oval = _ovalFor(size);
    final grow = 1 + 0.015 * v;
    final o = Rect.fromCenter(center: oval.center, width: oval.width * grow, height: oval.height * grow);
    canvas.drawOval(
      o,
      Paint()
        ..color = color.withValues(alpha: 0.25 + 0.15 * v)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );
    canvas.drawOval(
      o,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final b = o.inflate(18);
    final len = b.width * 0.12;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    void corner(Offset c, double dx, double dy) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + dy * len)
          ..lineTo(c.dx, c.dy)
          ..lineTo(c.dx + dx * len, c.dy),
        p,
      );
    }

    corner(b.topLeft, 1, 1);
    corner(b.topRight, -1, 1);
    corner(b.bottomLeft, 1, -1);
    corner(b.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.color != color || old.t != t;
}
