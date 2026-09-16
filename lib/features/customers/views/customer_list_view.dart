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
import 'package:enterprise_bike_showroom/features/customers/controllers/customer_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/models/customer_models.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Customer directory (desktop grid / mobile cards).
class CustomerListView extends GetView<CustomerController> {
  const CustomerListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Customers',
      actions: <Widget>[
        AppPermissionView(
          permission: Permissions.customersCreate,
          child: AppButton(
            label: 'Add Customer',
            icon: Icons.person_add_alt_1,
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
                    hint: 'Name, phone, email or code…',
                    onSearch: controller.updateSearch,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDropdown<String?>(
                    label: 'Type',
                    options: const <DropdownOption<String?>>[
                      DropdownOption<String?>(value: null, label: 'All'),
                      DropdownOption<String?>(value: 'retail', label: 'Retail'),
                      DropdownOption<String?>(value: 'dealer', label: 'Dealer'),
                      DropdownOption<String?>(value: 'corporate', label: 'Corporate'),
                      DropdownOption<String?>(value: 'financier', label: 'Financier'),
                    ],
                    value: controller.state.filters['customer_type'] as String?,
                    onChanged: (String? value) =>
                        controller.setFilter('customer_type', value),
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
                      DropdownOption<String?>(value: 'blocked', label: 'Blocked'),
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
                child: AppTable<CustomerModel>(
                  items: controller.items.value,
                  keyOf: (CustomerModel c) => c.id ?? '',
                  info: controller.pageInfo.value,
                  isLoading: controller.isLoading.value,
                  error: controller.errorMessage.value.isEmpty
                      ? null
                      : controller.errorMessage.value,
                  onRefresh: controller.refresh,
                  onPageChanged: controller.goToPage,
                  onPageSizeChanged: controller.setPageSize,
                  onRowTap: controller.openDetails,
                  emptyTitle: 'No customers yet',
                  emptyMessage: 'Add your first customer to start selling.',
                  columns: <AppColumn<CustomerModel>>[
                    AppColumn(
                      label: 'Code',
                      value: (CustomerModel c) =>
                          TableCells.text(c.customerCode, bold: true),
                    ),
                    AppColumn(
                      label: 'Name',
                      value: (CustomerModel c) =>
                          TableCells.text(c.name, bold: true),
                    ),
                    AppColumn(
                      label: 'Phone',
                      value: (CustomerModel c) =>
                          TableCells.text(AppFormatters.phone(c.phone)),
                    ),
                    AppColumn(
                      label: 'City',
                      value: (CustomerModel c) => TableCells.text(c.city),
                    ),
                    AppColumn(
                      label: 'Vehicles',
                      numeric: true,
                      value: (CustomerModel c) =>
                          TableCells.text('${c.vehicleCount}'),
                    ),
                    AppColumn(
                      label: 'Outstanding',
                      numeric: true,
                      value: (CustomerModel c) =>
                          TableCells.text(c.outstanding.currency),
                    ),
                    AppColumn(
                      label: 'Status',
                      value: (CustomerModel c) => AppStatusChip(status: c.status),
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
