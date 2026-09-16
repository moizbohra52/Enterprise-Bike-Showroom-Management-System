import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/sidebar_menu.dart';
import 'package:enterprise_bike_showroom/common/layouts/top_bar.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/core/constants/menu_constants.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/connectivity_service.dart';
import 'package:enterprise_bike_showroom/services/sync_service.dart';

/// Responsive application shell:
/// - Desktop: sidebar + top bar + breadcrumbs
/// - Mobile: app bar + drawer + bottom navigation
///
/// Every feature page wraps its content in [AppShell].
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.showBack = false,
    this.bottomNav,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;

  /// Adds a back arrow (sub-pages).
  final bool showBack;

  /// Mobile bottom-nav index override (defaults to the current route).
  final int? bottomNav;

  @override
  Widget build(BuildContext context) {
    final SessionController session = Get.find<SessionController>();
    final bool online = Get.find<ConnectivityService>().isOnline;
    final String route = Get.currentRoute;
    final String effectiveTitle =
        title ?? AppMenu.labelForRoute(_topRoute(route));

    if (context.isDesktop || context.isAppTablet) {
      return _DesktopShell(
        title: effectiveTitle,
        showBack: showBack,
        actions: actions,
        route: route,
        online: online,
        session: session,
        child: child,
      );
    }
    return _MobileShell(
      title: effectiveTitle,
      showBack: showBack,
      actions: actions,
      route: route,
      online: online,
      session: session,
      bottomNav: bottomNav,
      child: child,
    );
  }

  /// Top-level route for breadcrumbs (ignores /details/:id segments).
  static String _topRoute(String route) {
    final List<String> parts =
        route.split('/').where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return AppRoutes.dashboard;
    return '/${parts.first}';
  }
}

// ---------------------------------------------------------------- desktop

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.title,
    required this.showBack,
    required this.actions,
    required this.route,
    required this.online,
    required this.session,
    required this.child,
  });

  final String title;
  final bool showBack;
  final List<Widget>? actions;
  final String route;
  final bool online;
  final SessionController session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: <Widget>[
          SizedBox(
            width: 280,
            child: Container(
              color: theme.canvasColor,
              child: SidebarMenu(route: route, session: session),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: <Widget>[
                TopBar(
                  title: title,
                  showBack: showBack,
                  actions: actions,
                  online: online,
                  session: session,
                  desktop: true,
                ),
                if (!online) const _OfflineBanner(),
                Expanded(
                  child: Obx(() {
                    final SyncService? sync =
                        Get.isRegistered<SyncService>() ? Get.find<SyncService>() : null;
                    final int pending = sync?.pendingCount ?? 0;
                    return Column(
                      children: <Widget>[
                        if (pending > 0)
                          _SyncBanner(pending: pending, sync: sync!),
                        Expanded(child: SafeArea(child: child)),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- mobile

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.title,
    required this.showBack,
    required this.actions,
    required this.route,
    required this.online,
    required this.session,
    required this.bottomNav,
    required this.child,
  });

  final String title;
  final bool showBack;
  final List<Widget>? actions;
  final String route;
  final bool online;
  final SessionController session;
  final int? bottomNav;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AppMenuItem> navItems = AppMenu.mobileNav
        .where((AppMenuItem item) =>
            session.isSuperAdmin ||
            session.can(item.permission))
        .toList();

    int activeIndex = 0;
    for (int i = 0; i < navItems.length; i++) {
      if (route.startsWith(navItems[i].route) &&
          navItems[i].id != 'more') {
        activeIndex = i;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: showBack
            ? const BackButton()
            : Builder(
                builder: (BuildContext context) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  onPressed: () =>
                      Scaffold.of(context).openDrawer(),
                ),
              ),
        actions: <Widget>[
          ...?actions,
          const TopBarActions(
              desktop: false), // search / sync / bell / profile
        ],
      ),
      drawer: Drawer(
        child: SidebarMenu(route: route, session: session, compact: true),
      ),
      bottomNavigationBar: navItems.length > 1
          ? NavigationBar(
              selectedIndex: bottomNav ?? activeIndex,
              onDestinationSelected: (int index) {
                final AppMenuItem item = navItems[index];
                if (item.id == 'more') {
                  _openMoreSheet(context);
                  return;
                }
                if (item.route != route) {
                  Get.toNamed(item.route);
                }
              },
              destinations: <NavigationDestination>[
                for (final AppMenuItem item in navItems)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  ),
              ],
            )
          : null,
      body: Column(
        children: <Widget>[
          if (!online) const _OfflineBanner(),
          Expanded(child: SafeArea(child: child)),
        ],
      ),
    );
  }

  void _openMoreSheet(BuildContext context) {
    final List<AppMenuItem> all = AppMenu.visibleFor(
      session.permissions,
      isSuperAdmin: session.isSuperAdmin,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: <Widget>[
            for (final AppMenuItem item in all)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                selected: route.startsWith(item.route),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (item.route != route) Get.toNamed(item.route);
                },
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- sub-widgets

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Offline mode — changes are saved locally and will sync when '
              'you are back online.',
              style: TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.pending, required this.sync});

  final int pending;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primary.withAlpha(25),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          if (sync.isSyncing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.sync, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sync.isSyncing
                  ? 'Syncing $pending pending change${pending == 1 ? '' : 's'}…'
                  : '$pending pending change${pending == 1 ? '' : 's'} waiting to sync',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
            ),
          ),
          if (!sync.isSyncing)
            TextButton(
              onPressed: () => sync.syncNow(),
              child: const Text('Sync now', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
