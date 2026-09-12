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
import 'package:enterprise_bike_showroom/features/payments/controllers/payment_controller.dart';
import 'package:enterprise_bike_showroom/features/payments/models/payment_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Payment register.
class PaymentListView extends StatefulWidget {
  const PaymentListView({super.key});

  @override
  State<PaymentListView> createState() => _PaymentListViewState();
}

class _PaymentListViewState extends State<PaymentListView> {
  final PaymentController controller = Get.find<PaymentController>();

  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Payments',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.paymentsCreate,
          child: AppButton(
            label: 'New Payment',
            icon: Icons.payments,
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
                      hint: 'Payment no., reference or customer…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Mode',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'cash', label: 'Cash'),
                        DropdownOption<String?>(value: 'upi', label: 'UPI'),
                        DropdownOption<String?>(value: 'card', label: 'Card'),
                        DropdownOption<String?>(value: 'cheque', label: 'Cheque'),
                        DropdownOption<String?>(value: 'bank_transfer', label: 'Bank Transfer'),
                      ],
                      value: controller.state.filters['payment_mode'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('payment_mode', value),
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
                child: AppCard(
                  padding: 8,
                  child: AppTable<PaymentModel>(
                    items: controller.items.value,
                    keyOf: (PaymentModel p) => p.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (PaymentModel p) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.paymentDetails, p.id!)),
                    emptyTitle: 'No payments yet',
                    emptyMessage: 'Payments appear when you receive money.',
                    columns: <AppColumn<PaymentModel>>[
                      AppColumn(
                        label: 'Payment #',
                        value: (PaymentModel p) =>
                            TableCells.text(p.paymentNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Customer',
                        value: (PaymentModel p) =>
                            TableCells.text(p.customerName),
                      ),
                      AppColumn(
                        label: 'Date',
                        value: (PaymentModel p) =>
                            TableCells.text(AppFormatters.date(p.paymentDate)),
                      ),
                      AppColumn(
                        label: 'Amount',
                        numeric: true,
                        value: (PaymentModel p) =>
                            TableCells.text(p.amount.currency),
                      ),
                      AppColumn(
                        label: 'Mode',
                        value: (PaymentModel p) =>
                            TableCells.text(AppFormatters.humanize(p.paymentMode)),
                      ),
                      AppColumn(
                        label: 'Reference',
                        value: (PaymentModel p) =>
                            TableCells.text(p.referenceNumber ?? '-'),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (PaymentModel p) => AppStatusChip(
                            status: p.refunded ? 'refunded' : p.status),
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
      Get.toNamed(AppRoutes.paymentForm).then((_) => controller.refresh());
}
