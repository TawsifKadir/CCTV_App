import 'package:flutter/widgets.dart';

/// Layout breakpoints (logical pixels).
class Breakpoints {
  Breakpoints._();
  static const double tablet = 600;
  static const double desktop = 1024;
  static const double wide = 1440;
}

enum ScreenSize { mobile, tablet, desktop }

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  ScreenSize get screenSize {
    final w = screenWidth;
    if (w >= Breakpoints.desktop) return ScreenSize.desktop;
    if (w >= Breakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.mobile;
  }

  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;

  /// Whether the persistent sidebar navigation should be used.
  bool get useSidebar => screenWidth >= Breakpoints.tablet;

  /// Horizontal page padding appropriate for the current width.
  double get pagePadding {
    switch (screenSize) {
      case ScreenSize.mobile:
        return 20;
      case ScreenSize.tablet:
        return 28;
      case ScreenSize.desktop:
        return 40;
    }
  }
}

/// Picks a value based on the available width.
T responsiveValue<T>(
  BuildContext context, {
  required T mobile,
  T? tablet,
  T? desktop,
}) {
  switch (context.screenSize) {
    case ScreenSize.desktop:
      return desktop ?? tablet ?? mobile;
    case ScreenSize.tablet:
      return tablet ?? mobile;
    case ScreenSize.mobile:
      return mobile;
  }
}

/// Centers [child] and constrains it to a readable maximum width.
class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({super.key, required this.child, this.maxWidth = 1200});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
