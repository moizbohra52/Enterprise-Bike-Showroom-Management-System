import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';

/// Picks a builder by breakpoint.
///
/// - `desktop` (>= 900px): data grids, side-by-side forms
/// - `tablet` (>= 600px): 2-column grids
/// - `mobile` (< 600px):   cards, compact lists
class AppResponsiveLayout extends StatelessWidget {
  const AppResponsiveLayout({
    super.key,
    required this.desktop,
    required this.mobile,
    this.tablet,
  });

  final Widget Function(BuildContext context) desktop;
  final Widget Function(BuildContext context) mobile;

  /// Optional tablet layout; falls back to desktop.
  final Widget Function(BuildContext context)? tablet;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) return mobile(context);
    if (context.isAppTablet) {
      return (tablet ?? desktop)(context);
    }
    return desktop(context);
  }
}

/// Adaptive grid: 1 column mobile, 2 tablet, [desktopColumns] desktop.
class AppAdaptiveGrid extends StatelessWidget {
  const AppAdaptiveGrid({
    super.key,
    required this.children,
    this.desktopColumns = 3,
    this.tabletColumns = 2,
    this.crossAxisSpacing = 16,
    this.mainAxisSpacing = 16,
    this.childAspectRatio = 0.9,
  });

  final List<Widget> children;
  final int desktopColumns;
  final int tabletColumns;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    final int columns = context.isDesktop
        ? desktopColumns
        : context.isAppTablet
            ? tabletColumns
            : 1;
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      padding: EdgeInsets.zero,
      itemCount: children.length,
      itemBuilder: (BuildContext context, int index) => children[index],
    );
  }
}

/// Constrained content column (max width for long desktop pages).
class AppContentColumn extends StatelessWidget {
  const AppContentColumn({super.key, required this.child, this.maxWidth = 1400});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
