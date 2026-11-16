import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/motion.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_layout.dart';
import '../../../core/widgets/enrolly_logo.dart';

/// Split-screen layout on desktop (brand panel + form), stacked on mobile.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wide = context.screenWidth >= 900;
    final form = _FormColumn(title: title, subtitle: subtitle, leading: leading, child: child);
    return Scaffold(
      backgroundColor: p.background,
      body: wide
          ? Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(
                  flex: 6,
                  child: AppBackgroundDecor(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(Space.xxl),
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : AppBackgroundDecor(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xl),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: form),
                  ),
                ),
              ),
            ),
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({required this.title, required this.subtitle, required this.child, this.leading});

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final logo = const EnrollyLogoMark(size: 56);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(height: Space.md)],
        if (context.reduceMotion) logo else _PopIn(child: logo),
        const SizedBox(height: Space.lg),
        Text(title, style: t.headlineLarge).entrance(context, index: 1),
        const SizedBox(height: Space.xs),
        Text(subtitle, style: t.bodyLarge?.copyWith(color: context.palette.textMuted)).entrance(context, index: 2),
        const SizedBox(height: Space.lg),
        child.entrance(context, index: 3),
        const SizedBox(height: Space.lg),
        const Center(child: DemoNotice()),
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: p.nav, borderRadius: BorderRadius.circular(Radii.xl + 8)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -90,
            top: -60,
            child: _ring(320, AppColors.peach.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: -70,
            bottom: -90,
            child: _ring(260, Colors.white.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EnrollyLogo(size: 44, light: true),
                const Spacer(),
                const _ScanIllustration().entrance(context),
                const SizedBox(height: Space.xxl),
                Text(
                  AppConstants.tagline,
                  style: t.displaySmall?.copyWith(color: Colors.white, height: 1.15),
                ).entrance(context, index: 1),
                const SizedBox(height: Space.md),
                Text(
                  'Register employees with a photo, and the server builds their face template for recognition. Search and browse every record in one place.',
                  style: t.bodyLarge?.copyWith(color: Colors.white70),
                ).entrance(context, index: 2),
                const SizedBox(height: Space.lg),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: const [
                    _Feature(icon: Icons.photo_camera_front_outlined, label: 'Camera or upload'),
                    _Feature(icon: Icons.manage_search_rounded, label: 'Search & filter'),
                    _Feature(icon: Icons.dns_outlined, label: 'Multi-environment'),
                  ],
                ).entrance(context, index: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.peach),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

/// Decorative face-frame illustration for the brand panel.
class _ScanIllustration extends StatelessWidget {
  const _ScanIllustration();

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 260,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const EnrollyLogoMark(size: 64, background: AppColors.peachSoft),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(110, 0.5),
                const SizedBox(height: 8),
                _bar(80, 0.25),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text('Registered',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.success)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (context.reduceMotion) return card;
    return _Float(child: card);
  }

  Widget _bar(double w, double a) => Container(
        width: w,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: a),
          borderRadius: BorderRadius.circular(5),
        ),
      );
}

/// One-shot elastic pop-in for the logo (transform-only, no rebuilds).
class _PopIn extends StatefulWidget {
  const _PopIn({required this.child});
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  late final _scale = Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.elasticOut));
  late final _fade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.5));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: ScaleTransition(scale: _scale, child: widget.child));
}

/// Gentle floating motion for the decorative card. It is isolated in a
/// RepaintBoundary and only moves a layer (no rebuilds); previously this
/// used a flutter_animate effect chain that rebuilt the card every frame.
class _Float extends StatefulWidget {
  const _Float({required this.child});
  final Widget child;

  @override
  State<_Float> createState() => _FloatState();
}

class _FloatState extends State<_Float> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
  late final _offset = Tween(begin: const Offset(0, -0.025), end: const Offset(0, 0.025))
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: SlideTransition(position: _offset, child: widget.child));
}
