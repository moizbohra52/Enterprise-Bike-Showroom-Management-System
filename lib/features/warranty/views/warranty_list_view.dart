import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/warranty/controllers/warranty_controller.dart';
import 'package:enterprise_bike_showroom/features/warranty/models/warranty_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Warranty register.
class WarrantyListView extends GetView<WarrantyController> {
  const WarrantyListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Warranties',
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
                      hint: 'Warranty no., customer or registration…',
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
                        DropdownOption<String?>(value: 'voided', label: 'Voided'),
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
                child: AppCard(
                  padding: 8,
                  child: AppTable<WarrantyModel>(
                    items: controller.items.value,
                    keyOf: (WarrantyModel w) => w.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (WarrantyModel w) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.warrantyDetails, w.id!)),
                    emptyTitle: 'No warranties',
                    emptyMessage: 'Warranties are created on vehicle delivery.',
                    columns: <AppColumn<WarrantyModel>>[
                      AppColumn(
                        label: 'Warranty #',
                        value: (WarrantyModel w) =>
                            TableCells.text(w.warrantyNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Vehicle',
                        value: (WarrantyModel w) =>
                            TableCells.text(w.vehicleLabel),
                      ),
                      AppColumn(
                        label: 'Customer',
                        value: (WarrantyModel w) =>
                            TableCells.text(w.customerName),
                      ),
                      AppColumn(
                        label: 'Type',
                        value: (WarrantyModel w) =>
                            TableCells.text(AppFormatters.humanize(w.type)),
                      ),
                      AppColumn(
                        label: 'From',
                        value: (WarrantyModel w) =>
                            TableCells.text(AppFormatters.date(w.startDate)),
                      ),
                      AppColumn(
                        label: 'Till',
                        value: (WarrantyModel w) =>
                            TableCells.text(AppFormatters.date(w.endDate)),
                      ),
                      AppColumn(
                        label: 'Claims',
                        numeric: true,
                        value: (WarrantyModel w) =>
                            TableCells.text('${w.claimsCount}'),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (WarrantyModel w) =>
                            AppStatusChip(status: w.status),
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
}
