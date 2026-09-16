import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_date_picker.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/billing/controllers/invoice_controller.dart';
import 'package:enterprise_bike_showroom/features/billing/models/invoice_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Invoice register.
class InvoiceListView extends StatefulWidget {
  const InvoiceListView({super.key});

  @override
  State<InvoiceListView> createState() => _InvoiceListViewState();
}

class _InvoiceListViewState extends State<InvoiceListView> {
  final InvoiceController controller = Get.find<InvoiceController>();

  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Invoices',
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
                      hint: 'Invoice no. or customer…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Status',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'unpaid', label: 'Unpaid'),
                        DropdownOption<String?>(value: 'partial', label: 'Partial'),
                        DropdownOption<String?>(value: 'paid', label: 'Paid'),
                        DropdownOption<String?>(value: 'overdue', label: 'Overdue'),
                        DropdownOption<String?>(value: 'void', label: 'Void'),
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
                  child: AppTable<InvoiceModel>(
                    items: controller.items.value,
                    keyOf: (InvoiceModel i) => i.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (InvoiceModel i) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.invoiceDetails, i.id!)),
                    emptyTitle: 'No invoices yet',
                    emptyMessage: 'Invoices are generated when a sale completes.',
                    columns: <AppColumn<InvoiceModel>>[
                      AppColumn(
                        label: 'Invoice #',
                        value: (InvoiceModel i) =>
                            TableCells.text(i.invoiceNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Customer',
                        value: (InvoiceModel i) =>
                            TableCells.text(i.customerName),
                      ),
                      AppColumn(
                        label: 'Date',
                        value: (InvoiceModel i) =>
                            TableCells.text(AppFormatters.date(i.invoiceDate)),
                      ),
                      AppColumn(
                        label: 'Due',
                        value: (InvoiceModel i) =>
                            TableCells.text(AppFormatters.date(i.dueDate)),
                      ),
                      AppColumn(
                        label: 'Total',
                        numeric: true,
                        value: (InvoiceModel i) =>
                            TableCells.text(i.totalAmount.currency),
                      ),
                      AppColumn(
                        label: 'Paid',
                        numeric: true,
                        value: (InvoiceModel i) =>
                            TableCells.text(i.paidAmount.currency),
                      ),
                      AppColumn(
                        label: 'Outstanding',
                        numeric: true,
                        value: (InvoiceModel i) => TableCells.text(
                            i.outstandingAmount.currency,
                            color: i.outstandingAmount > 0
                                ? const Color(0xFFDC2626)
                                : null),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (InvoiceModel i) =>
                            AppStatusChip(status: i.status),
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
