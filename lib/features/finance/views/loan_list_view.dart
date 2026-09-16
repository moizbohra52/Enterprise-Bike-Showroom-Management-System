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
import 'package:enterprise_bike_showroom/features/finance/controllers/loan_controller.dart';
import 'package:enterprise_bike_showroom/features/finance/models/loan_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Loan register.
class LoanListView extends GetView<LoanController> {
  const LoanListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Loans',
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
                      hint: 'Loan no. or customer…',
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
                        DropdownOption<String?>(value: 'closed', label: 'Closed'),
                        DropdownOption<String?>(value: 'defaulted', label: 'Defaulted'),
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
                  child: AppTable<LoanModel>(
                    items: controller.items.value,
                    keyOf: (LoanModel l) => l.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (LoanModel l) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.loanDetails, l.id!)),
                    emptyTitle: 'No loans yet',
                    emptyMessage: 'Loans appear with EMI sales.',
                    columns: <AppColumn<LoanModel>>[
                      AppColumn(
                        label: 'Loan #',
                        value: (LoanModel l) =>
                            TableCells.text(l.loanNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Customer',
                        value: (LoanModel l) => TableCells.text(l.customerName),
                      ),
                      AppColumn(
                        label: 'Amount',
                        numeric: true,
                        value: (LoanModel l) =>
                            TableCells.text(l.loanAmount.currency),
                      ),
                      AppColumn(
                        label: 'EMI',
                        numeric: true,
                        value: (LoanModel l) =>
                            TableCells.text('${l.monthlyEmi.currency} × ${l.tenureMonths}'),
                      ),
                      AppColumn(
                        label: 'Outstanding',
                        numeric: true,
                        value: (LoanModel l) => TableCells.text(
                            l.outstandingAmount.currency,
                            color: l.outstandingAmount > 0
                                ? const Color(0xFFDC2626)
                                : null),
                      ),
                      AppColumn(
                        label: 'Starts',
                        value: (LoanModel l) =>
                            TableCells.text(AppFormatters.date(l.startDate)),
                      ),
                      AppColumn(
                        label: 'Ends',
                        value: (LoanModel l) =>
                            TableCells.text(AppFormatters.date(l.endDate)),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (LoanModel l) =>
                            AppStatusChip(status: l.status),
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
