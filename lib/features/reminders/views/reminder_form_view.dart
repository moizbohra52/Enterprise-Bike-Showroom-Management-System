import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_date_picker.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/features/reminders/controllers/reminder_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// New reminder.
class ReminderFormView extends GetView<ReminderFormController> {
  const ReminderFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'New Reminder',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Save',
            icon: Icons.save_outlined,
            isLoading: controller.saving.value,
            onPressed: () => _submit(context),
          ),
        ),
      ],
      child: Obx(() {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (controller.error.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(controller.error.value,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFFDC2626))),
                  ),
                AppTextField(
                  label: 'Title *',
                  onChanged: (String value) =>
                      controller.title.value = value,
                ),
                AppTextField(
                  label: 'Message',
                  maxLines: 3,
                  onChanged: (String value) =>
                      controller.message.value = value,
                ),
                AppDatePicker(
                  label: 'Reminder date',
                  value: controller.date.value,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  onChanged: (DateTime? value) =>
                      controller.date.value = value,
                ),
                AppDropdown<String>(
                  label: 'Type',
                  options: const <DropdownOption<String>>[
                    DropdownOption(value: 'custom', label: 'Custom'),
                    DropdownOption(value: 'service_due', label: 'Service due'),
                    DropdownOption(value: 'insurance_renewal', label: 'Insurance renewal'),
                    DropdownOption(value: 'warranty_expiry', label: 'Warranty expiry'),
                  ],
                  value: controller.type.value,
                  onChanged: (String? value) =>
                      controller.type.value = value ?? 'custom',
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final bool ok = await controller.submit();
    if (ok) {
      AppSnackbar.success(context, 'Reminder saved');
      Get.until((route) => route.settings.name == AppRoutes.reminders);
    }
  }
}
