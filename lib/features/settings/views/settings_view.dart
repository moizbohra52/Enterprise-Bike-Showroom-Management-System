import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/showroom/controllers/showroom_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Settings: preferences, active showroom, account.
class SettingsView extends GetView<AppStateController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionController session = Get.find<SessionController>();
    final ShowroomController showrooms = Get.find<ShowroomController>();

    return AppShell(
      title: 'Settings',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AppCard(
            title: 'Preferences',
            child: Column(
              children: <Widget>[
                AppDropdown<ThemeMode>(
                  label: 'Theme',
                  options: const <DropdownOption<ThemeMode>>[
                    DropdownOption(value: ThemeMode.system, label: 'System default'),
                    DropdownOption(value: ThemeMode.light, label: 'Light'),
                    DropdownOption(value: ThemeMode.dark, label: 'Dark'),
                  ],
                  value: controller.themeMode.value,
                  onChanged: (ThemeMode? value) =>
                      value != null ? controller.setThemeMode(value) : null,
                ),
                AppDropdown<String>(
                  label: 'Language',
                  options: const <DropdownOption<String>>[
                    DropdownOption(value: 'en', label: 'English'),
                    DropdownOption(value: 'hi', label: 'हिन्दी (coming soon)'),
                  ],
                  value: controller.language.value,
                  onChanged: (String? v) { if (v != null) controller.setLanguage(v); },
                ),
                AppDropdown<int>(
                  label: 'Rows per page',
                  options: const <DropdownOption<int>>[
                    DropdownOption(value: 20, label: '20'),
                    DropdownOption(value: 50, label: '50'),
                    DropdownOption(value: 100, label: '100'),
                  ],
                  value: controller.pageSize.value,
                  onChanged: (int? value) =>
                      controller.setPageSize(value ?? 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: 'Active showroom',
            subtitle: 'All lists and actions apply to this showroom '
                '(super admins may switch freely).',
            child: AppDropdown<String>(
              label: 'Showroom',
              options: <DropdownOption<String>>[
                for (final s in showrooms.items)
                  if (s.id != null)
                    DropdownOption<String>(value: s.id!, label: s.name),
              ],
              value: session.activeShowroomId.isEmpty
                  ? null
                  : session.activeShowroomId,
              onChanged: session.can(Permissions.showroomEdit)
                  ? (String? id) {
                      if (id != null) session.setActiveShowroom(id);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: 'Notifications',
            subtitle: 'In-app and push alerts for due EMIs, services and '
                'renewals.',
            child: SwitchListTile(
              title: const Text('Push notifications'),
              subtitle: const Text('Uses Firebase Cloud Messaging'),
              value: controller.notificationsEnabled.value,
              onChanged: controller.setNotificationsEnabled,
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: 'Tax',
            subtitle:
                'Default GST rate used on new sales (server keeps the source of truth).',
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AppDropdown<num>(
                    label: 'Default tax rate (%)',
                    options: const <DropdownOption<num>>[
                      DropdownOption(value: 0, label: '0%'),
                      DropdownOption(value: 5, label: '5%'),
                      DropdownOption(value: 12, label: '12%'),
                      DropdownOption(value: 18, label: '18%'),
                    ],
                    value: session.taxRate,
                    onChanged: (num? value) =>
                        value != null ? session.setTaxRate(value) : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: 'Account',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _kv('Signed in as', session.user.value?.name ?? '-'),
                _kv('Role', session.roleNames.join(', ').isEmpty ? 'User' : session.roleNames.join(', ')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    _tile(Icons.person_outline, 'My Profile',
                        () => Get.toNamed(AppRoutes.users)),
                    _tile(Icons.logout, 'Sign out',
                        () => Get.find<AuthController>().signOut()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '${AppConfig.appName} v${AppConfig.appVersion}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: const Color(0xFF94A3B8)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
