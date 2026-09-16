import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_date_picker.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/sales/controllers/sale_controller.dart';
import 'package:enterprise_bike_showroom/features/sales/models/sale_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Sales register (StatefulWidget: local date-filter state).
class SaleListView extends StatefulWidget {
  const SaleListView({super.key});

  @override
  State<SaleListView> createState() => _SaleListViewState();
}

class _SaleListViewState extends State<SaleListView> {
  final SaleController controller = Get.find<SaleController>();

  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Sales',
      actions: <Widget>[
        AppPermissionView(
          permission: Permissions.salesCreate,
          child: AppButton(
            label: 'New Sale',
            icon: Icons.point_of_sale,
            onPressed: _newSale,
          ),
        ),
      ],
      child: _content(),
    );
  }

  void _newSale() => Get.toNamed(AppRoutes.saleForm)?.then((_) => controller.refresh());

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
                    hint: 'Sale no. or customer…',
                    onSearch: controller.updateSearch,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDropdown<String?>(
                    label: 'Status',
                    options: const <DropdownOption<String?>>[
                      DropdownOption<String?>(value: null, label: 'All'),
                      DropdownOption<String?>(value: 'completed', label: 'Completed'),
                      DropdownOption<String?>(value: 'pending', label: 'Pending'),
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
                  child: AppDatePicker(
                    label: 'From',
                    value: _dateFrom,
                    firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                    lastDate: DateTime.now(),
                    onChanged: (DateTime? value) {
                      setState(() => _dateFrom = value);
                      controller.setFilter('date_from',
                          value?.toIso8601String().substring(0, 10));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDatePicker(
                    label: 'To',
                    value: _dateTo,
                    firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                    lastDate: DateTime.now(),
                    onChanged: (DateTime? value) {
                      setState(() => _dateTo = value);
                      controller.setFilter('date_to',
                          value?.toIso8601String().substring(0, 10));
                    },
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
                child: AppTable<SaleModel>(
                  items: controller.items.value,
                  keyOf: (SaleModel s) => s.id ?? '',
                  info: controller.pageInfo.value,
                  isLoading: controller.isLoading.value,
                  error: controller.errorMessage.value.isEmpty
                      ? null
                      : controller.errorMessage.value,
                  onRefresh: controller.refresh,
                  onPageChanged: controller.goToPage,
                  onPageSizeChanged: controller.setPageSize,
                  onRowTap: (SaleModel s) => Get.toNamed(
                      AppRoutes.withId(AppRoutes.saleDetails, s.id!)),
                  emptyTitle: 'No sales yet',
                  emptyMessage: 'Create your first sale to get started.',
                  columns: <AppColumn<SaleModel>>[
                    AppColumn(
                      label: 'Sale #',
                      value: (SaleModel s) =>
                          TableCells.text(s.saleNumber, bold: true),
                    ),
                    AppColumn(
                      label: 'Customer',
                      value: (SaleModel s) => TableCells.text(s.customerName),
                    ),
                    AppColumn(
                      label: 'Date',
                      value: (SaleModel s) =>
                          TableCells.text(AppFormatters.date(s.saleDate)),
                    ),
                    AppColumn(
                      label: 'Vehicle',
                      value: (SaleModel s) =>
                          TableCells.text(s.vehicleLine?.name ?? '-'),
                    ),
                    AppColumn(
                      label: 'Total',
                      numeric: true,
                      value: (SaleModel s) => TableCells.text(s.totalAmount.currency),
                    ),
                    AppColumn(
                      label: 'Paid',
                      numeric: true,
                      value: (SaleModel s) => TableCells.text(s.paidAmount.currency),
                    ),
                    AppColumn(
                      label: 'Balance',
                      numeric: true,
                      value: (SaleModel s) =>
                          TableCells.text(s.balanceAmount.currency,
                              color: s.balanceAmount > 0
                                  ? const Color(0xFFDC2626)
                                  : null),
                    ),
                    AppColumn(
                      label: 'Mode',
                      value: (SaleModel s) =>
                          TableCells.text(AppFormatters.humanize(s.paymentMode),
                              bold: s.emi),
                    ),
                    AppColumn(
                      label: 'Status',
                      value: (SaleModel s) => AppStatusChip(status: s.status),
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
