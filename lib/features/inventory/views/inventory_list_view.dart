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
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/inventory/controllers/inventory_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/models/inventory_models.dart';

/// Inventory list with status/product filters.
class InventoryListView extends GetView<InventoryController> {
  const InventoryListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Inventory',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.inventoryCreate,
          child: AppButton(
            label: 'Stock In',
            icon: Icons.inventory_2,
            onPressed: _stockIn,
          ),
        ),
        const SizedBox(width: 8),
        const AppPermissionView(
          permission: Permissions.inventoryTransfer,
          child: AppButton(
            label: 'Transfer',
            icon: Icons.swap_horiz,
            variant: AppButtonVariant.outlined,
            onPressed: _transfer,
          ),
        ),
      ],
      child: _content(),
    );
  }

  void _stockIn() => controller.openStockIn();
  void _transfer() => controller.openTransfer();

  Widget _content() {
    return Padding(
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
                    hint: 'Chassis, engine or stock code…',
                    onSearch: controller.updateSearch,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDropdown<String?>(
                    label: 'Status',
                    options: const <DropdownOption<String?>>[
                      DropdownOption<String?>(value: null, label: 'All'),
                      DropdownOption<String?>(value: 'available', label: 'Available'),
                      DropdownOption<String?>(value: 'reserved', label: 'Reserved'),
                      DropdownOption<String?>(value: 'sold', label: 'Sold'),
                      DropdownOption<String?>(value: 'demo', label: 'Demo'),
                      DropdownOption<String?>(value: 'damaged', label: 'Damaged'),
                      DropdownOption<String?>(value: 'in_transit', label: 'In Transit'),
                      DropdownOption<String?>(value: 'returned', label: 'Returned'),
                    ],
                    value: controller.state.filters['status'] as String?,
                    onChanged: (String? value) =>
                        controller.setFilter('status', value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(
                    () => AppDropdown<String?>(
                      label: 'Product',
                      options: controller.productOptions,
                      value: controller.state.filters['product_id'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('product_id', value),
                    ),
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
                child: AppTable<InventoryModel>(
                  items: controller.items.value,
                  keyOf: (InventoryModel i) => i.id ?? '',
                  info: controller.pageInfo.value,
                  isLoading: controller.isLoading.value,
                  error: controller.errorMessage.value.isEmpty
                      ? null
                      : controller.errorMessage.value,
                  onRefresh: controller.refresh,
                  onPageChanged: controller.goToPage,
                  onPageSizeChanged: controller.setPageSize,
                  onRowTap: controller.openDetails,
                  emptyTitle: 'No stock yet',
                  emptyMessage: 'Use Stock In to add bikes to inventory.',
                  columns: <AppColumn<InventoryModel>>[
                    AppColumn(
                      label: 'Stock Code',
                      value: (InventoryModel i) =>
                          TableCells.text(i.stockCode, bold: true),
                    ),
                    AppColumn(
                      label: 'Product',
                      value: (InventoryModel i) =>
                          TableCells.text(i.productLabel),
                    ),
                    AppColumn(
                      label: 'Chassis',
                      value: (InventoryModel i) =>
                          TableCells.text(i.chassisNumber),
                    ),
                    AppColumn(
                      label: 'Engine',
                      value: (InventoryModel i) =>
                          TableCells.text(i.engineNumber),
                    ),
                    AppColumn(
                      label: 'Purchase',
                      numeric: true,
                      value: (InventoryModel i) =>
                          TableCells.text(i.purchasePrice.currency),
                    ),
                    AppColumn(
                      label: 'Status',
                      value: (InventoryModel i) =>
                          AppStatusChip(status: i.status),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
