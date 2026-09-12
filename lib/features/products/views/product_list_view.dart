import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_image.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/products/controllers/product_controller.dart';
import 'package:enterprise_bike_showroom/features/products/models/product_models.dart';

/// Product (bike) catalog list.
class ProductListView extends GetView<ProductController> {
  const ProductListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Products',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.productsCreate,
          child: AppButton(
            label: 'Add Product',
            icon: Icons.add,
            onPressed: _add,
          ),
        ),
      ],
      child: _content(),
    );
  }

  void _add() => controller.openForm();

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
                    hint: 'Search name, model, variant…',
                    onSearch: controller.updateSearch,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(
                    child: AppDropdown<String?>(
                      options: controller.brandOptions,
                      value: controller.state.filters['brand_id'] as String?,
                      onChanged: controller.applyBrandFilter,
                    ),
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
                child: AppTable<ProductModel>(
                  items: controller.items.value,
                  keyOf: (ProductModel p) => p.id ?? '',
                  info: controller.pageInfo.value,
                  isLoading: controller.isLoading.value,
                  error: controller.errorMessage.value.isEmpty
                      ? null
                      : controller.errorMessage.value,
                  onRefresh: controller.refresh,
                  onPageChanged: controller.goToPage,
                  onPageSizeChanged: controller.setPageSize,
                  onRowTap: controller.openDetails,
                  emptyTitle: 'No products yet',
                  emptyMessage: 'Add your first bike to the catalog.',
                  leadingCell: (ProductModel p) => AppImage(
                    url: p.primaryImageUrl,
                    width: 44,
                    height: 32,
                    radius: 6,
                  ),
                  columns: <AppColumn<ProductModel>>[
                    AppColumn(
                      label: 'Product',
                      value: (ProductModel p) => TableCells.text(p.fullName, bold: true),
                    ),
                    AppColumn(
                      label: 'Brand',
                      value: (ProductModel p) =>
                          TableCells.text(p.brand?.name ?? '-'),
                    ),
                    AppColumn(
                      label: 'Engine',
                      value: (ProductModel p) => TableCells.text(
                          p.engineCc == null ? '-' : '${p.engineCc} cc'),
                    ),
                    AppColumn(
                      label: 'Selling Price',
                      numeric: true,
                      value: (ProductModel p) =>
                          TableCells.text(p.sellingPrice.currency),
                    ),
                    AppColumn(
                      label: 'Warranty',
                      value: (ProductModel p) =>
                          TableCells.text('${p.warrantyMonths} mo'),
                    ),
                    AppColumn(
                      label: 'Status',
                      value: (ProductModel p) => AppStatusChip(status: p.status),
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
