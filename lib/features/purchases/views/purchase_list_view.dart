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

/// Purchase register.
class PurchaseListView extends GetView<PurchaseController> {
  const PurchaseListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Purchases',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.purchasesCreate,
          child: AppButton(
            label: 'New Purchase',
            icon: Icons.shopping_cart_outlined,
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
                      hint: 'Purchase no. or supplier…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Status',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'ordered', label: 'Ordered'),
                        DropdownOption<String?>(value: 'partial', label: 'Partially Received'),
                        DropdownOption<String?>(value: 'received', label: 'Received'),
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
                  child: AppTable<PurchaseModel>(
                    items: controller.items.value,
                    keyOf: (PurchaseModel p) => p.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (PurchaseModel p) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.purchaseDetails, p.id!)),
                    emptyTitle: 'No purchases yet',
                    emptyMessage: 'Raise a purchase order to restock.',
                    columns: <AppColumn<PurchaseModel>>[
                      AppColumn(
                        label: 'Purchase #',
                        value: (PurchaseModel p) =>
                            TableCells.text(p.purchaseNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Supplier',
                        value: (PurchaseModel p) =>
                            TableCells.text(p.supplierName),
                      ),
                      AppColumn(
                        label: 'Ordered',
                        value: (PurchaseModel p) =>
                            TableCells.text(AppFormatters.date(p.orderDate)),
                      ),
                      AppColumn(
                        label: 'Expected',
                        value: (PurchaseModel p) =>
                            TableCells.text(AppFormatters.date(p.expectedDate)),
                      ),
                      AppColumn(
                        label: 'Total',
                        numeric: true,
                        value: (PurchaseModel p) =>
                            TableCells.text(p.totalAmount.currency),
                      ),
                      AppColumn(
                        label: 'Paid',
                        numeric: true,
                        value: (PurchaseModel p) =>
                            TableCells.text(p.paidAmount.currency),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (PurchaseModel p) =>
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

  void _new() =>
      Get.toNamed(AppRoutes.purchaseForm).then((_) => controller.refresh());
}
