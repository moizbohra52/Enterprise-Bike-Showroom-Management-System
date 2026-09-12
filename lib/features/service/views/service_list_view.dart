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
import 'package:enterprise_bike_showroom/features/service/controllers/service_controller.dart';
import 'package:enterprise_bike_showroom/features/service/models/service_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Workshop board.
class ServiceListView extends GetView<ServiceController> {
  const ServiceListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Service',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.serviceCreate,
          child: AppButton(
            label: 'New Job Card',
            icon: Icons.engineering,
            onPressed: _new,
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
                      hint: 'Job no., customer or registration…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Status',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'in_progress', label: 'In Progress'),
                        DropdownOption<String?>(value: 'waiting_parts', label: 'Waiting Parts'),
                        DropdownOption<String?>(value: 'ready', label: 'Ready'),
                        DropdownOption<String?>(value: 'delivered', label: 'Delivered'),
                        DropdownOption<String?>(value: 'cancelled', label: 'Cancelled'),
                      ],
                      value: controller.state.filters['status'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('status', value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Type',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'paid', label: 'Paid'),
                        DropdownOption<String?>(value: 'free', label: 'Free'),
                        DropdownOption<String?>(value: 'warranty', label: 'Warranty'),
                      ],
                      value: controller.state.filters['job_type'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('job_type', value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(
                child: AppCard(
                  padding: 8,
                  child: AppTable<ServiceRecordModel>(
                    items: controller.items.value,
                    keyOf: (ServiceRecordModel s) => s.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (ServiceRecordModel s) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.serviceDetails, s.id!)),
                    emptyTitle: 'No job cards',
                    emptyMessage: 'Open a job card when a vehicle arrives.',
                    columns: <AppColumn<ServiceRecordModel>>[
                      AppColumn(
                        label: 'Job #',
                        value: (ServiceRecordModel s) =>
                            TableCells.text(s.serviceNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Customer',
                        value: (ServiceRecordModel s) =>
                            TableCells.text(s.customerName),
                      ),
                      AppColumn(
                        label: 'Vehicle',
                        value: (ServiceRecordModel s) =>
                            TableCells.text(s.vehicleLabel),
                      ),
                      AppColumn(
                        label: 'Type',
                        value: (ServiceRecordModel s) =>
                            TableCells.text(AppFormatters.humanize(s.jobType),
                                bold: s.jobType != 'paid'),
                      ),
                      AppColumn(
                        label: 'Date',
                        value: (ServiceRecordModel s) =>
                            TableCells.text(AppFormatters.date(s.serviceDate)),
                      ),
                      AppColumn(
                        label: 'Total',
                        numeric: true,
                        value: (ServiceRecordModel s) =>
                            TableCells.text(s.totalAmount.currency),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (ServiceRecordModel s) =>
                            AppStatusChip(status: s.status),
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

  void _new() =>
      Get.toNamed(AppRoutes.serviceForm).then((_) => controller.refresh());
}
