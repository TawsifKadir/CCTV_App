import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/app_spacing.dart';

/// Reduced-motion aware animation helpers.
///
/// `MediaQuery.disableAnimations` is set from both the OS accessibility
/// setting and the in-app "Reduce motion" preference (see `app.dart`).
extension MotionContext on BuildContext {
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  Duration motion(Duration d) => reduceMotion ? Duration.zero : d;
}

extension EntranceAnimation on Widget {
  /// Fade + slide-up entrance, staggered by [index].
  ///
  /// Performance notes (this used to be the main source of list jank):
  /// * Only the first [maxAnimated] items animate; later ones (usually off
  ///   screen) appear immediately instead of each owning a controller.
  /// * One controller drives both effects, and the widget subtree is built
  ///   once — the animation only changes the opacity/transform layers.
  /// * No-op with reduced motion.
  Widget entrance(
    BuildContext context, {
    int index = 0,
    double dy = 0.04,
    Duration? delay,
    int maxAnimated = 8,
  }) {
    if (context.reduceMotion || index >= maxAnimated) return this;
    final stagger = Duration(milliseconds: 40 * index);
    return _Entrance(delay: (delay ?? Duration.zero) + stagger, dy: dy, child: this);
  }
}

class _Entrance extends StatefulWidget {
  const _Entrance({required this.delay, required this.dy, required this.child});

  final Duration delay;
  final double dy;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Motion.curve);
  late final Animation<Offset> _offset = Tween(begin: Offset(0, widget.dy), end: Offset.zero).animate(_curve);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(widget.delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
