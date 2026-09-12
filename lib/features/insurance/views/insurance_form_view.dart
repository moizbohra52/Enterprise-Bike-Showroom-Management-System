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
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/insurance/controllers/insurance_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Add insurance policy.
class InsuranceFormView extends GetView<InsuranceFormController> {
  const InsuranceFormView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.init());

    return AppShell(
      title: 'Add Policy',
      showBack: true,
      actions: <Widget>[
        Obx(
          child: AppButton(
            label: 'Save Policy',
            icon: Icons.save_outlined,
            isLoading: controller.saving,
            onPressed: () => _submit(),
          ),
        ),
      ],
      child: Obx(() {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (controller.error.value.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(controller.error.value,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFDC2626))),
                ),
              AppCard(
                title: 'Vehicle',
                child: Column(
                  children: <Widget>[
                    AppDropdown<String?>(
                      label: 'Customer',
                      options: <DropdownOption<String>>[
                        for (final Map<String, dynamic> c
                            in controller.customers.value)
                          DropdownOption<String>(
                            value: SafeJson.asId(c['id']) ?? '',
                            label:
                                '${c['name'] ?? ''} · ${c['phone'] ?? ''}',
                          ),
                      ],
                      value: controller.customerId.value,
                      onChanged: (String? value) => value != null &&
                              value.isNotEmpty
                          ? controller.selectCustomer(value)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    AppDropdown<String?>(
                      label: 'Vehicle',
                      options: <DropdownOption<String>>[
                        for (final Map<String, dynamic> v
                            in controller.vehicles.value)
                          DropdownOption<String>(
                            value: SafeJson.asId(v['id']) ?? '',
                            label: '${v['registration_number'] ?? ''} · '
                                '${v['chassis_number'] ?? ''}',
                          ),
                      ],
                      value: controller.vehicleId.value,
                      onChanged: (String? value) =>
                          controller.vehicleId.value = value,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Policy',
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppTextField(
                            label: 'Insurer',
                            onChanged: (String value) =>
                                controller.insurer.value = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Policy number',
                            onChanged: (String value) =>
                                controller.policyNumber.value = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppDropdown<String>(
                      label: 'Policy type',
                      options: const <DropdownOption<String>>[
                        DropdownOption(
                            value: 'comprehensive', label: 'Comprehensive'),
                        DropdownOption(
                            value: 'third_party', label: 'Third Party'),
                        DropdownOption(value: 'personal_accident',
                            label: 'Personal Accident'),
                      ],
                      value: controller.policyType.value,
                      onChanged: (String? value) =>
                          controller.policyType.value = value ??
                          'comprehensive',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppDatePicker(
                            label: 'Start date',
                            value: controller.startDate.value,
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            onChanged: (DateTime? value) =>
                                controller.startDate.value = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppDatePicker(
                            label: 'End date',
                            value: controller.endDate.value,
                            lastDate: DateTime.now().add(const Duration(days: 1825)),
                            onChanged: (DateTime? value) =>
                                controller.endDate.value = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppTextField(
                            label: 'Premium (₹)',
                            keyboardType: TextInputType.number,
                            onChanged: (String value) => controller.premium
                                    .value =
                                double.tryParse(value) ??
                            0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Coverage amount (₹)',
                            keyboardType: TextInputType.number,
                            onChanged: (String value) => controller.coverage
                                    .value =
                                double.tryParse(value) ??
                            0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _submit() async {
    final bool ok = await controller.submit();
    if (ok) {
      AppSnackbar.success(context, 'Policy saved');
      Get.until((route) => route.settings.name == AppRoutes.insurance);
    }
  }
}
