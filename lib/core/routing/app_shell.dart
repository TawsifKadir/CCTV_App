import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/providers/auth_controller.dart';
import '../../features/connectivity/app_features_provider.dart';
import '../../features/connectivity/connectivity_widgets.dart';
import '../../features/environments/presentation/widgets/environment_widgets.dart';
import '../../features/sync/presentation/sync_providers.dart';
import '../../features/sync/presentation/sync_widgets.dart';
import '../config/app_features.dart';
import '../../features/authentication/widgets/dev_login_tools.dart' show DemoModeBadge;
import '../../features/environments/presentation/providers/environment_providers.dart' show isDemoSessionProvider;
import '../../features/settings/screens/settings_screen.dart' show confirmLogout;
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../utils/motion.dart';
import '../utils/responsive.dart';
import '../widgets/enrolly_logo.dart';
import 'routes.dart';

class NavDestination {
  const NavDestination(this.path, this.label, this.icon, this.activeIcon, {this.shortLabel});
  final String path;
  final String label;
  final String? shortLabel;
  final IconData icon;
  final IconData activeIcon;
}

const _dashboard = NavDestination(
  Routes.home,
  'Dashboard',
  Icons.space_dashboard_outlined,
  Icons.space_dashboard_rounded,
  shortLabel: 'Home',
);
const _employees = NavDestination(
  Routes.employees,
  'Employee Management',
  Icons.people_alt_outlined,
  Icons.people_alt_rounded,
  shortLabel: 'Employees',
);
const _register = NavDestination(
  Routes.enroll,
  'Register Employee',
  Icons.person_add_alt_outlined,
  Icons.person_add_alt_1_rounded,
  shortLabel: 'Register',
);
const _sync = NavDestination(
  Routes.sync,
  'Synchronization',
  Icons.cloud_sync_outlined,
  Icons.cloud_sync_rounded,
  shortLabel: 'Sync',
);
const _diagnostics = NavDestination(
  Routes.diagnostics,
  'Diagnostics',
  Icons.bug_report_outlined,
  Icons.bug_report_rounded,
);
const _settings = NavDestination(Routes.settings, 'Settings', Icons.tune_outlined, Icons.tune_rounded);
const _environment = NavDestination(
  Routes.environment,
  'Environment Configuration',
  Icons.dns_outlined,
  Icons.dns_rounded,
  shortLabel: 'Environment',
);

/// Mobile bottom bar (both modes): Dashboard, Employees, [Register], Sync, Settings.
const mobileDestinations = [_dashboard, _employees, _register, _sync, _settings];

/// Desktop sidebar (Logout is rendered separately at the bottom). Admin
/// builds add environment configuration and diagnostics.
List<NavDestination> sidebarDestinations(AppFeatures f) => [
  _dashboard,
  _employees,
  _register,
  _sync,
  _settings,
  if (f.environmentConfiguration) _environment,
  if (f.networkInspector) _diagnostics,
];

bool _isActive(String location, String path) => location == path || location.startsWith('$path/');

/// User preference for the desktop sidebar; `null` = automatic
/// (collapsed on tablet, expanded on desktop).
class SidebarCollapsed extends Notifier<bool?> {
  @override
  bool? build() => null;
  void toggle(bool current) => state = !current;
}

final sidebarCollapsedProvider = NotifierProvider<SidebarCollapsed, bool?>(SidebarCollapsed.new);

/// Responsive application frame: bottom navigation on phones, a collapsible
/// charcoal sidebar on tablets and desktops. In debug-capable environments
/// a thin strip at the top names the backend in use.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // Connectivity monitoring + automatic sync live as long as the shell.
    ref.watch(syncCoordinatorProvider);
    // The status bar consumes the top safe-area inset; remove it from the
    // page so it isn't applied twice.
    final page = Column(
      children: [
        const ShellStatusBar(),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );

    if (context.useSidebar) {
      final pref = ref.watch(sidebarCollapsedProvider);
      final collapsed = pref ?? !context.isDesktop;
      return Scaffold(
        backgroundColor: p.background,
        body: Row(
          children: [
            AppSidebar(location: location, collapsed: collapsed),
            Expanded(child: page),
          ],
        ),
      );
    }
    final showNav = !Routes.hidesBottomNav(location);
    return Scaffold(
      backgroundColor: p.background,
      extendBody: true,
      body: page,
      bottomNavigationBar: showNav ? AppBottomNavigation(location: location) : null,
    );
  }
}

/// Floating charcoal bottom bar with an elevated central Register button.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = [mobileDestinations[0], mobileDestinations[1], mobileDestinations[3], mobileDestinations[4]];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 92,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 70,
                decoration: BoxDecoration(
                  color: p.nav,
                  borderRadius: BorderRadius.circular(Radii.xl),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < 2; i++)
                      Expanded(
                        child: _NavItem(dest: items[i], active: _isActive(location, items[i].path)),
                      ),
                    const SizedBox(width: 76),
                    for (var i = 2; i < 4; i++)
                      Expanded(
                        child: _NavItem(dest: items[i], active: _isActive(location, items[i].path)),
                      ),
                  ],
                ),
              ),
              const Positioned(top: 0, child: _CenterRegisterButton()),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.dest, required this.active});

  final NavDestination dest;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final label = dest.shortLabel ?? dest.label;
    final color = active ? AppColors.peach : Colors.white.withValues(alpha: 0.72);
    return Semantics(
      selected: active,
      button: true,
      label: label,
      child: InkResponse(
        onTap: () => context.go(dest.path),
        radius: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? dest.activeIcon : dest.icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: color, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Central "Register" action.
///
/// Performance: the halo used to pulse forever via an AnimatedBuilder that
/// rebuilt two Containers every frame, keeping the whole app rendering at
/// 60 fps even when idle. It now pulses three times after appearing and is
/// drawn by a painter (no rebuilds) inside its own RepaintBoundary.
class _CenterRegisterButton extends StatefulWidget {
  const _CenterRegisterButton();

  @override
  State<_CenterRegisterButton> createState() => _CenterRegisterButtonState();
}

class _CenterRegisterButtonState extends State<_CenterRegisterButton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
  bool _down = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _pulse.stop();
    } else if (!_started) {
      _started = true;
      _pulse.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = context.palette.background;
    return Semantics(
      button: true,
      label: 'Register employee',
      child: GestureDetector(
        key: const Key('nav-register'),
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () => context.go(Routes.enroll),
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: context.motion(Motion.fast),
          child: SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(child: CustomPaint(painter: _HaloPainter(_pulse))),
                ),
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.peach,
                    shape: BoxShape.circle,
                    border: Border.all(color: bg, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.peach.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final v = anim.value;
    if (v == 0 || v == 1) return;
    canvas.drawCircle(
      size.center(Offset.zero),
      30 + 8 * v,
      Paint()..color = AppColors.peach.withValues(alpha: 0.28 * (1 - v)),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.anim != anim;
}

/// Collapsible charcoal sidebar for tablet/desktop.
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, required this.location, required this.collapsed});

  final String location;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final operator = ref.watch(authControllerProvider);
    final width = collapsed ? 88.0 : 268.0;

    return AnimatedContainer(
      duration: context.motion(Motion.medium),
      curve: Motion.curve,
      width: width,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.nav,
        borderRadius: BorderRadius.circular(Radii.xl),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.xl),
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 4),
                    const EnrollyLogoMark(size: 40),
                    if (!collapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppConstants.appName, style: t.titleLarge?.copyWith(color: Colors.white)),
                            Text(
                              'Identity management',
                              style: t.labelSmall?.copyWith(color: Colors.white54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _CollapseButton(collapsed: collapsed),
                    ],
                  ],
                ),
                if (collapsed) ...[const SizedBox(height: 12), Center(child: _CollapseButton(collapsed: collapsed))],
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                _SidebarRegisterButton(collapsed: collapsed),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final d in sidebarDestinations(ref.watch(appFeaturesProvider)))
                        _SidebarItem(
                          key: Key('nav-${d.path}'),
                          label: d.label,
                          icon: _isActive(location, d.path) ? d.activeIcon : d.icon,
                          active: _isActive(location, d.path),
                          collapsed: collapsed,
                          onTap: () => context.go(d.path),
                        ),
                    ],
                  ),
                ),
                if (operator != null && !collapsed) ...[
                  _OperatorCard(name: operator.operator.fullName, email: operator.operator.username),
                  const SizedBox(height: 8),
                ],
                _SidebarItem(
                  key: const Key('nav-logout'),
                  label: 'Logout',
                  icon: Icons.logout_rounded,
                  active: false,
                  collapsed: collapsed,
                  onTap: () => confirmLogout(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapseButton extends ConsumerWidget {
  const _CollapseButton({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      onPressed: () => ref.read(sidebarCollapsedProvider.notifier).toggle(collapsed),
      icon: Icon(
        collapsed ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded,
        color: Colors.white70,
        size: 20,
      ),
    );
  }
}

class _SidebarRegisterButton extends StatelessWidget {
  const _SidebarRegisterButton({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Tooltip(
      message: collapsed ? 'Register employee' : '',
      child: Material(
        color: AppColors.peach,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md + 2),
          onTap: () => context.go(Routes.enroll),
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded, color: Colors.white),
                if (!collapsed) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'New Employee',
                      style: t.labelLarge?.copyWith(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = widget.active;
    final fg = active ? AppColors.peach : Colors.white.withValues(alpha: _hover ? 0.95 : 0.7);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: widget.collapsed ? widget.label : '',
        waitDuration: const Duration(milliseconds: 300),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Semantics(
            selected: active,
            button: true,
            label: widget.label,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.08)
                      : (_hover ? Colors.white.withValues(alpha: 0.04) : Colors.transparent),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  mainAxisAlignment: widget.collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Icon(widget.icon, color: fg, size: 22),
                    if (!widget.collapsed) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: t.labelLarge?.copyWith(
                            color: fg,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.md + 2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.peach.withValues(alpha: 0.2),
            child: Text(
              Fmt.initials(name),
              style: t.labelMedium?.copyWith(color: AppColors.peach, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: t.labelLarge?.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: t.labelSmall?.copyWith(color: Colors.white54),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Top status bar on every screen: connectivity, pending uploads and (on
/// wide layouts) Sync now. Admin builds also show the environment badge;
/// client builds never show environment details.
class ShellStatusBar extends ConsumerWidget {
  const ShellStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(appFeaturesProvider);
    final wide = context.useSidebar;
    final p = context.palette;
    return Material(
      color: p.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(context.pagePadding, wide ? 10 : 6, context.pagePadding, wide ? 0 : 2),
          child: SizedBox(
            height: wide ? 46 : 30,
            child: Row(
              children: [
                // Scrolls instead of overflowing on narrow phones.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (!kProductionBuild && ref.watch(isDemoSessionProvider)) ...[
                          const DemoModeBadge(),
                          const SizedBox(width: Space.xs),
                        ],
                        if (features.environmentIndicator) ...[
                          const EnvironmentBadge(dense: true),
                          const SizedBox(width: Space.xs),
                        ],
                        const ConnectivityPill(),
                        const SizedBox(width: Space.xs),
                        const PendingSyncChip(),
                      ],
                    ),
                  ),
                ),
                if (wide) const SyncNowButton(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
