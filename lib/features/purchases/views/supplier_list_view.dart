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
import 'package:enterprise_bike_showroom/features/purchases/controllers/purchase_controller.dart';
import 'package:enterprise_bike_showroom/features/purchases/models/purchase_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Supplier directory.
class SupplierListView extends GetView<SupplierController> {
  const SupplierListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Suppliers',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.purchasesCreate,
          child: AppButton(
            label: 'Add Supplier',
            icon: Icons.apartment_outlined,
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
                      hint: 'Name, phone, city or GSTIN…',
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
                        DropdownOption<String?>(value: 'inactive', label: 'Inactive'),
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
                  child: AppTable<SupplierModel>(
                    items: controller.items.value,
                    keyOf: (SupplierModel s) => s.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: _edit,
                    emptyTitle: 'No suppliers yet',
                    emptyMessage: 'Add your first supplier to raise purchases.',
                    columns: <AppColumn<SupplierModel>>[
                      AppColumn(
                        label: 'Supplier',
                        value: (SupplierModel s) =>
                            TableCells.text(s.name, bold: true),
                      ),
                      AppColumn(
                        label: 'Contact',
                        value: (SupplierModel s) =>
                            TableCells.text(s.contactPerson),
                      ),
                      AppColumn(
                        label: 'Phone',
                        value: (SupplierModel s) =>
                            TableCells.text(AppFormatters.phone(s.phone)),
                      ),
                      AppColumn(
                        label: 'City',
                        value: (SupplierModel s) => TableCells.text(s.city),
                      ),
                      AppColumn(
                        label: 'GSTIN',
                        value: (SupplierModel s) =>
                            TableCells.text(s.gstin.isEmpty ? '-' : s.gstin),
                      ),
                      AppColumn(
                        label: 'Terms',
                        numeric: true,
                        value: (SupplierModel s) =>
                            TableCells.text('${s.paymentTermsDays} days'),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (SupplierModel s) =>
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

  void _add() => Get.toNamed(AppRoutes.supplierForm).then(
        (_) => controller.refresh(),
      );

  void _edit(SupplierModel supplier) => Get.toNamed(
        AppRoutes.withId(AppRoutes.supplierForm, supplier.id!),
      ).then((_) => controller.refresh());
}
