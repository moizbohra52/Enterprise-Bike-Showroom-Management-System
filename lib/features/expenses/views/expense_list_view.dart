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
import 'package:enterprise_bike_showroom/features/expenses/controllers/expense_controller.dart';
import 'package:enterprise_bike_showroom/features/expenses/models/expense_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Expense register.
class ExpenseListView extends StatefulWidget {
  const ExpenseListView({super.key});

  @override
  State<ExpenseListView> createState() => _ExpenseListViewState();
}

class _ExpenseListViewState extends State<ExpenseListView> {
  final ExpenseController controller = Get.find<ExpenseController>();

  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Expenses',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.expensesCreate,
          child: AppButton(
            label: 'New Expense',
            icon: Icons.receipt_outlined,
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
                      hint: 'Number, description or voucher…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Status',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'pending', label: 'Pending'),
                        DropdownOption<String?>(value: 'approved', label: 'Approved'),
                        DropdownOption<String?>(value: 'rejected', label: 'Rejected'),
                        DropdownOption<String?>(value: 'paid', label: 'Paid'),
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
                  child: AppTable<ExpenseModel>(
                    items: controller.items.value,
                    keyOf: (ExpenseModel e) => e.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (ExpenseModel e) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.expenseDetails, e.id!)),
                    emptyTitle: 'No expenses yet',
                    emptyMessage: 'Record office, rent, salary and other costs.',
                    columns: <AppColumn<ExpenseModel>>[
                      AppColumn(
                        label: '#',
                        value: (ExpenseModel e) =>
                            TableCells.text(e.expenseNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Date',
                        value: (ExpenseModel e) =>
                            TableCells.text(AppFormatters.date(e.date)),
                      ),
                      AppColumn(
                        label: 'Category',
                        value: (ExpenseModel e) =>
                            TableCells.text(e.categoryLabel),
                      ),
                      AppColumn(
                        label: 'Description',
                        value: (ExpenseModel e) =>
                            TableCells.text(e.description),
                      ),
                      AppColumn(
                        label: 'Amount',
                        numeric: true,
                        value: (ExpenseModel e) =>
                            TableCells.text(e.amount.currency),
                      ),
                      AppColumn(
                        label: 'Voucher',
                        value: (ExpenseModel e) =>
                            TableCells.text(e.voucherNumber.isEmpty ? '-' : e.voucherNumber),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (ExpenseModel e) =>
                            AppStatusChip(status: e.status),
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
      Get.toNamed(AppRoutes.expenseForm).then((_) => controller.refresh());
}
