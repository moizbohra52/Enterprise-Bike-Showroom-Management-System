import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/sync_state_controller.dart';
import 'package:enterprise_bike_showroom/common/layouts/showroom_selector.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_avatar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/core/constants/menu_constants.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/notifications/controllers/notification_controller.dart';
import 'package:enterprise_bike_showroom/features/search/controllers/search_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Top bar: title (+back), search, showroom selector, sync, bell, profile.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    this.showBack = false,
    this.actions,
    this.online = true,
    required this.session,
    this.desktop = true,
  });

  final String title;
  final bool showBack;
  final List<Widget>? actions;
  final bool online;
  final SessionController session;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 64,
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          if (showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Get.back(),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (desktop) _Breadcrumbs(),
              ],
            ),
          ),
          ...?actions,
          const SizedBox(width: 8),
          const TopBarActions(desktop: true),
        ],
      ),
    );
  }
}

/// Breadcrumb row under the page title (desktop only).
class _Breadcrumbs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final String route = Get.currentRoute;
    final List<String> crumbs =
        route.split('/').where((String p) => p.isNotEmpty).toList();
    final ThemeData theme = Theme.of(context);
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final String topLabel = AppMenu.labelForRoute('/${crumbs.first}');
    return Row(
      children: <Widget>[
        Text('Home', style: theme.textTheme.labelSmall),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right, size: 12),
        ),
        Text(topLabel, style: theme.textTheme.labelSmall),
        if (crumbs.length > 2) ...<Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right, size: 12),
          ),
          Flexible(
            child: Text(
              crumbs.length == 3 ? 'Details' : crumbs.last,
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// Search / sync / notifications / profile cluster (app bar + top bar).
class TopBarActions extends StatelessWidget {
  const TopBarActions({super.key, this.desktop = true});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final SessionController session = Get.find<SessionController>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (desktop)
          const SizedBox(
            width: 320,
            child: AppSearchField(
              hint: 'Search customers, bikes, invoices…',
              onSearch: (String q) => _openSearch(context, q),
            ),
          ),
        if (desktop)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: ShowroomSelector(),
          ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Global search',
          onPressed: () => _openSearch(context, ''),
        ),
        const _SyncIndicator(),
        const _NotificationBell(),
        const SizedBox(width: 4),
        _ProfileMenu(session: session),
      ],
    );
  }

  void _openSearch(BuildContext context, String initial) {
    final SearchController search = Get.find<SearchController>();
    search.openWith(initial);
  }
}

class _SyncIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final SyncStateController? syncState =
        Get.isRegistered<SyncStateController>()
            ? Get.find<SyncStateController>()
            : null;
    if (syncState == null) return const SizedBox.shrink();
    return Obx(() {
      final int pending = syncState.pendingCount.value;
      final bool syncing = syncState.isSyncing.value;
      if (pending == 0 && !syncing) return const SizedBox.shrink();
      return Tooltip(
        message: '$pending pending change${pending == 1 ? '' : 's'}',
        child: Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending',
              style: const TextStyle(fontSize: 10, color: Colors.white)),
          child: const Icon(Icons.sync_problem_outlined),
        ),
      );
    });
  }
}

class _NotificationBell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final NotificationController notifications =
        Get.find<NotificationController>();
    return Obx(() {
      final int unread = notifications.unreadCount.value;
      return IconButton(
        tooltip: 'Notifications',
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread',
              style: const TextStyle(fontSize: 10, color: Colors.white)),
          child: const Icon(Icons.notifications_outlined),
        ),
        onPressed: () => Get.toNamed(AppRoutes.notifications),
      );
    });
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (String value) {
        switch (value) {
          case 'profile':
            Get.toNamed(AppRoutes.settings);
          case 'settings':
            Get.toNamed(AppRoutes.settings);
          case 'logout':
            _confirmLogout(context);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'profile', child: Text('Profile')),
        const PopupMenuItem<String>(value: 'settings', child: Text('Settings')),
        const PopupMenuItem<String>(value: 'logout', child: Text('Sign out')),
      ],
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: AppAvatar(
          name: session.displayName,
          imageUrl: session.user.value?.avatarUrl,
          size: 34,
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final bool confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will be signed out of this device.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await session.clearSession();
    }
  }
}
