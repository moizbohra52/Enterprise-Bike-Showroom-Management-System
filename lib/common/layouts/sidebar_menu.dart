import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/constants/menu_constants.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Desktop sidebar (and mobile drawer content): permission-aware menu.
class SidebarMenu extends StatelessWidget {
  const SidebarMenu({
    super.key,
    required this.route,
    required this.session,
    this.compact = false,
  });

  final String route;
  final SessionController session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final items = AppMenu.visibleFor(
      session.permissions,
      isSuperAdmin: session.isSuperAdmin,
    );

    return Column(
      children: <Widget>[
        _brand(theme),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: <Widget>[
              for (final AppMenuItem item in items)
                _MenuItemTile(
                  item: item,
                  active: route.startsWith(item.route),
                  compact: compact,
                ),
            ],
          ),
        ),
        _footer(theme),
      ],
    );
  }

  Widget _brand(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.two_wheeler, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(AppConfig.appName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  session.displayName,
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(border: Border(top: BorderSide())),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${AppConfig.appName} ${AppConfig.appVersion}',
              style: theme.textTheme.labelSmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            tooltip: 'Sign out',
            onPressed: () => session.clearSession(),
          ),
        ],
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({
    required this.item,
    required this.active,
    required this.compact,
  });

  final AppMenuItem item;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: () {
        if (item.route != Get.currentRoute) {
          Get.toNamed(item.route);
          if (compact) Navigator.of(context).pop();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary.withAlpha(26) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              item.icon,
              size: 20,
              color: active ? theme.colorScheme.primary : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: active ? theme.colorScheme.primary : null,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (active) const Icon(Icons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}
