import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/insurance/controllers/insurance_controller.dart';
import 'package:enterprise_bike_showroom/features/insurance/models/insurance_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Insurance register.
class InsuranceListView extends GetView<InsuranceController> {
  const InsuranceListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Insurance',
      actions: <Widget>[
        AppPermissionView(
          permission: Permissions.insuranceCreate,
          child: AppButton(
            label: 'Add Policy',
            icon: Icons.policy_outlined,
            onPressed: _add,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            AppCard(
              padding: 12,
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: AppSearchField(
                      hint: 'Policy no., insurer or customer…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Status',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'active', label: 'Active'),
                        DropdownOption<String?>(value: 'expired', label: 'Expired'),
                        DropdownOption<String?>(value: 'cancelled', label: 'Cancelled'),
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
              child: Obx(
                () => AppCard(
                  padding: 8,
                  child: AppTable<InsurancePolicyModel>(
                    items: controller.items.value,
                    keyOf: (InsurancePolicyModel p) => p.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (InsurancePolicyModel p) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.insuranceDetails, p.id!)),
                    emptyTitle: 'No policies',
                    emptyMessage: 'Add policies to track renewals and coverage.',
                    columns: <AppColumn<InsurancePolicyModel>>[
                      AppColumn(
                        label: 'Policy #',
                        value: (InsurancePolicyModel p) =>
                            TableCells.text(p.policyNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Vehicle',
                        value: (InsurancePolicyModel p) =>
                            TableCells.text(p.vehicleLabel),
                      ),
                      AppColumn(
                        label: 'Customer',
                        value: (InsurancePolicyModel p) =>
                            TableCells.text(p.customerName),
                      ),
                      AppColumn(
                        label: 'Insurer',
                        value: (InsurancePolicyModel p) =>
                            TableCells.text(p.insurer),
                      ),
                      AppColumn(
                        label: 'Valid till',
                        value: (InsurancePolicyModel p) {
                          final bool soon = p.expiringSoon;
                          return TableCells.text(
                            AppFormatters.date(p.endDate),
                            color: soon ? const Color(0xFFD97706) : null,
                          );
                        },
                      ),
                      AppColumn(
                        label: 'Premium',
                        numeric: true,
                        value: (InsurancePolicyModel p) =>
                            TableCells.text(p.premium.currency),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (InsurancePolicyModel p) =>
                            AppStatusChip(status: p.status),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _add() =>
      Get.toNamed(AppRoutes.insuranceForm)?.then((_) => controller.refresh());
}
