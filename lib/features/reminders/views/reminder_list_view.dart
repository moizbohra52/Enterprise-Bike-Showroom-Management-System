import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/reminders/controllers/reminder_controller.dart';
import 'package:enterprise_bike_showroom/features/reminders/models/reminder_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Reminder center.
class ReminderListView extends GetView<ReminderController> {
  const ReminderListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Reminders',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.remindersCreate,
          child: AppButton(
            label: 'New Reminder',
            icon: Icons.add_alert_outlined,
            onPressed: _add,
          ),
        ),
      ],
      child: Obx(() {
        final List<ReminderModel> rows = controller.items.value;
        final int pending = rows
            .where((ReminderModel r) => r.status == 'pending').length;
        final int overdue = rows.where((ReminderModel r) {
          if (r.status != 'pending' || r.reminderDate == null) return false;
          return r.reminderDate!.isBefore(DateTime.now());
        }).length;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppStatCard(
                        title: 'Pending (page)',
                        value: '$pending',
                        icon: Icons.notifications_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppStatCard(
                        title: 'Overdue',
                        value: '$overdue',
                        icon: Icons.warning_amber,
                        color: overdue > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF16A34A)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: 12,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: AppSearchField(
                        hint: 'Title, message or customer…',
                        onSearch: controller.updateSearch,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppDropdown<String?>(
                        label: 'Type',
                        options: const <DropdownOption<String?>>[
                          DropdownOption<String?>(value: null, label: 'All'),
                          DropdownOption<String?>(value: 'emi_due', label: 'EMI Due'),
                          DropdownOption<String?>(value: 'service_due', label: 'Service Due'),
                          DropdownOption<String?>(value: 'insurance_renewal', label: 'Insurance'),
                          DropdownOption<String?>(value: 'warranty_expiry', label: 'Warranty'),
                          DropdownOption<String?>(value: 'custom', label: 'Custom'),
                        ],
                        value: controller.state.filters['type'] as String?,
                        onChanged: (String? value) =>
                            controller.setFilter('type', value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppDropdown<String?>(
                        label: 'Status',
                        options: const <DropdownOption<String?>>[
                          DropdownOption<String?>(value: null, label: 'All'),
                          DropdownOption<String?>(value: 'pending', label: 'Pending'),
                          DropdownOption<String?>(value: 'done', label: 'Done'),
                          DropdownOption<String?>(value: 'dismissed', label: 'Dismissed'),
                        ],
                        value: controller.state.filters['status'] as String?,
                        onChanged: (String? value) =>
                            controller.setFilter('status', value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: controller.isLoading.value && rows.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
                        ? const Center(
                            child: Text('No reminders.',
                                style:
                                    TextStyle(color: Color(0xFF64748B))))
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (BuildContext context, int index) {
                              final ReminderModel r = rows[index];
                              final bool isOverdue = r.status == 'pending' &&
                                  r.reminderDate != null &&
                                  r.reminderDate!.isBefore(DateTime.now());
                              return Card(
                                child: ListTile(
                                  leading: Icon(
                                    _iconFor(r.type),
                                    color: isOverdue
                                        ? const Color(0xFFDC2626)
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                  title: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(r.title,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w600)),
                                      ),
                                      AppStatusChip(status: r.status),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        '${AppFormatters.date(r.reminderDate)}'
                                        '${r.customerName.isEmpty ? '' : ' · ${r.customerName}'}'
                                        '${r.message.isEmpty ? '' : ' · ${r.message}'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      if (isOverdue)
                                        const Text('Overdue',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFFDC2626),
                                                fontWeight:
                                                    FontWeight.w600)),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: r.status == 'pending'
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            IconButton(
                                              tooltip: 'Mark done',
                                              icon: const Icon(Icons.check),
                                              onPressed: () async {
                                                final bool ok =
                                                    await controller.markDone(r);
                                                if (ok) controller.refresh();
                                              },
                                            ),
                                            IconButton(
                                              tooltip: 'Dismiss',
                                              icon: const Icon(Icons.close),
                                              onPressed: () async {
                                                final bool ok =
                                                    await controller.dismiss(r);
                                                if (ok) controller.refresh();
                                              },
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      }),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'emi_due':
        return Icons.request_quote;
      case 'service_due':
        return Icons.engineering;
      case 'insurance_renewal':
        return Icons.policy;
      case 'warranty_expiry':
        return Icons.verified_user;
      default:
        return Icons.notifications;
    }
  }

  void _add() =>
      Get.toNamed(AppRoutes.remindersForm).then((_) => controller.refresh());
}
