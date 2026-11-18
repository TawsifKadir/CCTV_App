import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/motion.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_layout.dart';
import '../../../core/widgets/brand_surface.dart';
import '../../../core/widgets/enrolly_logo.dart';

/// Split-screen layout on desktop (brand panel + form), stacked on mobile.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? leading;

  /// Optional content under the form (e.g. environment info).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wide = context.screenWidth >= 900;
    final form = _FormColumn(title: title, subtitle: subtitle, leading: leading, footer: footer, child: child);
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
          : SingleChildScrollView(
              child: Column(
                children: [
                  const _MobileHero(),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: _FormColumn(
                          title: title,
                          subtitle: subtitle,
                          leading: leading,
                          footer: footer,
                          showLogo: false,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
    this.footer,
    this.showLogo = true,
  });

  final bool showLogo;

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? leading;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final logo = Row(
      children: [
        const EnrollyLogoMark(size: 52),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppConstants.appName, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(AppConstants.tagline, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(height: Space.md)],
        if (showLogo) ...[if (context.reduceMotion) logo else _PopIn(child: logo), const SizedBox(height: Space.lg)],
        Text(title, style: t.headlineLarge).entrance(context, index: 1),
        const SizedBox(height: Space.xs),
        Text(subtitle, style: t.bodyLarge?.copyWith(color: context.palette.textMuted)).entrance(context, index: 2),
        const SizedBox(height: Space.lg),
        child.entrance(context, index: 3),
        const SizedBox(height: Space.lg),
        ?footer,
      ],
    );
  }
}

/// Branded header for phones: gradient band with the logo.
class _MobileHero extends StatelessWidget {
  const _MobileHero();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final top = MediaQuery.paddingOf(context).top;
    return BrandSurface(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.xl + 10)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.lg, top + Space.xl, Space.lg, Space.xl),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(Radii.lg + 3),
              ),
              child: const EnrollyLogoMark(size: 58),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appName,
                    style: t.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppConstants.tagline,
                    style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).entrance(context);
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(Space.md),
      child: BrandSurface(
        borderRadius: BorderRadius.circular(Radii.xl + 8),
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EnrollyLogo(size: 44, light: true, showTagline: true),
              const Spacer(),
              const Center(child: _ScanIllustration()).entrance(context),
              const Spacer(),
              Text(
                'Enroll employees in seconds.',
                style: t.displaySmall?.copyWith(color: Colors.white, height: 1.15, fontWeight: FontWeight.w700),
              ).entrance(context, index: 1),
              const SizedBox(height: Space.sm),
              Text(
                'Capture a photo, enter the details, and the SNOWTEX server takes care of the rest.',
                style: t.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
              ).entrance(context, index: 2),
              const SizedBox(height: Space.lg),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Feature(icon: Icons.photo_camera_front_outlined, label: 'Take a photo or upload one'),
                  SizedBox(height: Space.sm),
                  _Feature(icon: Icons.cloud_sync_outlined, label: 'Works offline and syncs automatically'),
                  SizedBox(height: Space.sm),
                  _Feature(icon: Icons.manage_search_rounded, label: 'Search the whole employee directory'),
                ],
              ).entrance(context, index: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: Space.sm + 2),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Decorative enrollment card: an oval face guide and a "Registered" record,
/// with a second card peeking behind it.
class _ScanIllustration extends StatelessWidget {
  const _ScanIllustration();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget glass({required Widget child, double opacity = 0.12}) => Container(
      width: 300,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: child,
    );
    final front = glass(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.elliptical(20, 26)),
                  border: Border.all(color: AppColors.navAccent, width: 2),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white70, size: 30),
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(120, 0.55),
                const SizedBox(height: 8),
                _bar(86, 0.28),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8FE3BE).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF8FE3BE)),
                      const SizedBox(width: 4),
                      Text('Registered', style: t.labelSmall?.copyWith(color: const Color(0xFF8FE3BE))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final stack = SizedBox(
      width: 330,
      height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 30,
            top: 0,
            child: Transform.rotate(angle: 0.06, child: glass(opacity: 0.06, child: const SizedBox(height: 78))),
          ),
          Positioned(left: 0, top: 26, child: front),
        ],
      ),
    );
    if (context.reduceMotion) return stack;
    return _Float(child: stack);
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
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
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
  late final _offset = Tween(
    begin: const Offset(0, -0.025),
    end: const Offset(0, 0.025),
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SlideTransition(position: _offset, child: widget.child),
  );
}
