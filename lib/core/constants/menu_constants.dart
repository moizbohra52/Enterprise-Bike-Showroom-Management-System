import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';

/// A navigation menu entry (permission-aware).
class AppMenuItem {
  const AppMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    required this.permission,
    this.group = 'main',
  });

  final String id;
  final String label;
  final IconData icon;
  final String route;

  /// Required `module.view` permission to see this item.
  final String permission;

  /// Sidebar grouping.
  final String group;
}

/// The full application menu (order matters).
class AppMenu {
  AppMenu._();

  static const List<AppMenuItem> items = <AppMenuItem>[
    AppMenuItem(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      route: '/dashboard',
      permission: Permissions.dashboardView,
    ),
    AppMenuItem(
      id: 'showrooms',
      label: 'Showrooms',
      icon: Icons.storefront_outlined,
      route: '/showrooms',
      permission: Permissions.showroomView,
      group: 'administration',
    ),
    AppMenuItem(
      id: 'users',
      label: 'Users',
      icon: Icons.people_outline,
      route: '/users',
      permission: Permissions.usersView,
      group: 'administration',
    ),
    AppMenuItem(
      id: 'roles',
      label: 'Roles & Permissions',
      icon: Icons.shield_outlined,
      route: '/roles',
      permission: Permissions.rolesView,
      group: 'administration',
    ),
    AppMenuItem(
      id: 'products',
      label: 'Products',
      icon: Icons.pedals_outlined,
      route: '/products',
      permission: Permissions.productsView,
      group: 'catalog',
    ),
    AppMenuItem(
      id: 'inventory',
      label: 'Inventory',
      icon: Icons.inventory_2_outlined,
      route: '/inventory',
      permission: Permissions.inventoryView,
      group: 'catalog',
    ),
    AppMenuItem(
      id: 'purchases',
      label: 'Purchases',
      icon: Icons.shopping_cart_outlined,
      route: '/purchases',
      permission: Permissions.purchasesView,
      group: 'catalog',
    ),
    AppMenuItem(
      id: 'customers',
      label: 'Customers',
      icon: Icons.people_alt_outlined,
      route: '/customers',
      permission: Permissions.customersView,
      group: 'sales',
    ),
    AppMenuItem(
      id: 'sales',
      label: 'Sales',
      icon: Icons.point_of_sale_outlined,
      route: '/sales',
      permission: Permissions.salesView,
      group: 'sales',
    ),
    AppMenuItem(
      id: 'billing',
      label: 'Billing / Invoices',
      icon: Icons.receipt_long_outlined,
      route: '/billing',
      permission: Permissions.billingView,
      group: 'sales',
    ),
    AppMenuItem(
      id: 'payments',
      label: 'Payments',
      icon: Icons.payments_outlined,
      route: '/payments',
      permission: Permissions.paymentsView,
      group: 'sales',
    ),
    AppMenuItem(
      id: 'finance',
      label: 'Finance & Loans',
      icon: Icons.account_balance_outlined,
      route: '/finance',
      permission: Permissions.financeView,
      group: 'finance',
    ),
    AppMenuItem(
      id: 'emi',
      label: 'EMI',
      icon: Icons.request_quote_outlined,
      route: '/emi',
      permission: Permissions.emiView,
      group: 'finance',
    ),
    AppMenuItem(
      id: 'expenses',
      label: 'Expenses',
      icon: Icons.receipt_outlined,
      route: '/expenses',
      permission: Permissions.expensesView,
      group: 'finance',
    ),
    AppMenuItem(
      id: 'accounting',
      label: 'Accounting',
      icon: Icons.calculate_outlined,
      route: '/accounting',
      permission: Permissions.accountingView,
      group: 'finance',
    ),
    AppMenuItem(
      id: 'service',
      label: 'Service (Job Cards)',
      icon: Icons.engineering_outlined,
      route: '/service',
      permission: Permissions.serviceView,
      group: 'service',
    ),
    AppMenuItem(
      id: 'free-service',
      label: 'Free Service',
      icon: Icons.vacuum_cleaner_outlined,
      route: '/free-service',
      permission: Permissions.serviceView,
      group: 'service',
    ),
    AppMenuItem(
      id: 'warranty',
      label: 'Warranty',
      icon: Icons.verified_user_outlined,
      route: '/warranty',
      permission: Permissions.warrantyView,
      group: 'service',
    ),
    AppMenuItem(
      id: 'insurance',
      label: 'Insurance',
      icon: Icons.policy_outlined,
      route: '/insurance',
      permission: Permissions.insuranceView,
      group: 'service',
    ),
    AppMenuItem(
      id: 'reminders',
      label: 'Reminders',
      icon: Icons.notifications_none_outlined,
      route: '/reminders',
      permission: Permissions.remindersView,
      group: 'operations',
    ),
    AppMenuItem(
      id: 'reports',
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      route: '/reports',
      permission: Permissions.reportsView,
      group: 'operations',
    ),
    AppMenuItem(
      id: 'documents',
      label: 'Documents',
      icon: Icons.folder_outlined,
      route: '/documents',
      permission: Permissions.documentsView,
      group: 'operations',
    ),
    AppMenuItem(
      id: 'audit',
      label: 'Audit Logs',
      icon: Icons.history_outlined,
      route: '/audit',
      permission: Permissions.auditView,
      group: 'operations',
    ),
    AppMenuItem(
      id: 'notifications',
      label: 'Notifications',
      icon: Icons.notifications_outlined,
      route: '/notifications',
      permission: Permissions.notificationsView,
      group: 'operations',
    ),
    AppMenuItem(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      route: '/settings',
      permission: Permissions.settingsView,
    ),
  ];

  /// Mobile bottom nav items (max 5).
  static const List<AppMenuItem> mobileNav = <AppMenuItem>[
    AppMenuItem(
      id: 'dashboard',
      label: 'Home',
      icon: Icons.space_dashboard_outlined,
      route: '/dashboard',
      permission: Permissions.dashboardView,
    ),
    AppMenuItem(
      id: 'customers',
      label: 'Customers',
      icon: Icons.people_alt_outlined,
      route: '/customers',
      permission: Permissions.customersView,
    ),
    AppMenuItem(
      id: 'sales',
      label: 'Sales',
      icon: Icons.point_of_sale_outlined,
      route: '/sales',
      permission: Permissions.salesView,
    ),
    AppMenuItem(
      id: 'service',
      label: 'Service',
      icon: Icons.engineering_outlined,
      route: '/service',
      permission: Permissions.serviceView,
    ),
    AppMenuItem(
      id: 'more',
      label: 'More',
      icon: Icons.more_horiz,
      route: '/dashboard',
      permission: Permissions.dashboardView,
    ),
  ];

  /// Sidebar group titles.
  static const Map<String, String> groupTitles = <String, String>{
    'main': 'Overview',
    'administration': 'Administration',
    'catalog': 'Catalog & Stock',
    'sales': 'Sales & Billing',
    'finance': 'Finance',
    'service': 'Service & After-Sales',
    'operations': 'Operations',
  };

  /// Label for a route (breadcrumbs / page titles).
  static String labelForRoute(String route) {
    for (final AppMenuItem item in items) {
      if (item.route == route) return item.label;
    }
    return 'Dashboard';
  }

  /// Items the user may see, preserving menu order.
  static List<AppMenuItem> visibleFor(Iterable<String> permissions,
      {bool isSuperAdmin = false}) {
    return items.where((AppMenuItem item) {
      if (isSuperAdmin) return true;
      if (permissions.contains(item.permission)) return true;
      return permissions.contains(Permissions.moduleWildcard(
          _moduleOf(item.permission)));
    }).toList(growable: false);
  }

  static String _moduleOf(String permission) =>
      permission.split('.').first;
}
