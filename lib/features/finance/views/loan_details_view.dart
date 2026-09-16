import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dialog.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/finance/controllers/loan_controller.dart';
import 'package:enterprise_bike_showroom/features/finance/models/loan_models.dart';
import 'package:enterprise_bike_showroom/services/pdf_service.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Loan 360: summary + full EMI schedule + receive-EMI action.
class LoanDetailsView extends GetView<LoanDetailsController> {
  const LoanDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Loan', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Loan Details',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final LoanModel? loan = controller.loan.value;
          if (loan == null || loan.status != 'active') {
            return const SizedBox.shrink();
          }
          return AppButton(
            label: 'Receive EMI',
            icon: Icons.payments_outlined,
            onPressed: () => _receiveEmi(context),
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.loan.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Obx(() {
                if (controller.error.value.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.error_outline,
                              color: Color(0xFFDC2626)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(controller.error.value,
                                  style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
              _Header(),
              const SizedBox(height: 12),
              _Kpis(),
              const SizedBox(height: 12),
              _Schedule(),
            ],
          ),
        );
      }),
    );
  }

  String? _pathId() {
    final String? name = Get.currentRoute;
    if (name != null) {
      final List<String> parts = name.split('/');
      if (parts.isNotEmpty) return parts.last;
    }
    return null;
  }

  Future<void> _receiveEmi(BuildContext context) async {
    final LoanModel? loan = controller.loan.value;
    if (loan?.id == null) return;
    final List<EmiScheduleModel> payable = <EmiScheduleModel>[
      for (final EmiScheduleModel row in controller.schedule.value)
        if (row.status == 'upcoming' || row.status == 'due' || row.status == 'overdue' || row.status == 'partial')
          row,
    ];
    if (payable.isEmpty) {
      AppSnackbar.error(context, 'No installments due.');
      return;
    }
    final int? selected = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Receive EMI for'),
        children: <Widget>[
          for (final EmiScheduleModel row in payable)
            SimpleDialogOption(
              onPressed: () => Get.back(result: row.installmentNo),
              child: Text(
                'Installment ${row.installmentNo} of ${loan!.tenureMonths} — '
                '${AppFormatters.date(row.dueDate)} · ${row.emiAmount.currency} '
                '(${AppFormatters.humanize(row.status)})',
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final String? mode = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Payment mode'),
        children: <Widget>[
          SimpleDialogOption(onPressed: () => Get.back(result: 'cash'),
              child: const Text('Cash')),
          SimpleDialogOption(onPressed: () => Get.back(result: 'upi'),
              child: const Text('UPI')),
          SimpleDialogOption(onPressed: () => Get.back(result: 'cheque'),
              child: const Text('Cheque')),
          SimpleDialogOption(onPressed: () => Get.back(result: 'bank_transfer'),
              child: const Text('Bank Transfer')),
        ],
      ),
    );
    if (mode == null) return;
    final EmiScheduleModel row = payable.firstWhere(
        (EmiScheduleModel r) => r.installmentNo == selected);
    final bool ok = await controller.payInstallment(row, paymentMode: mode);
    if (ok) AppSnackbar.success(context, 'EMI received');
  }
}

class _Header extends GetView<LoanDetailsController> {
  @override
  Widget build(BuildContext context) {
    final LoanModel loan = controller.loan.value!;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(loan.loanNumber,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${loan.customerName} · '
                '${loan.method == 'flat' ? 'Flat' : 'Reducing'} '
                '${loan.interestRate.toStringAsFixed(2)}% p.a. · '
                '${loan.tenureMonths} months',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AppStatusChip(status: loan.status),
      ],
    );
  }
}

class _Kpis extends GetView<LoanDetailsController> {
  @override
  Widget build(BuildContext context) {
    final LoanModel loan = controller.loan.value!;
    return Row(
      children: <Widget>[
        Expanded(
          child: AppStatCard(
              title: 'Loan Amount',
              value: loan.loanAmount.currency,
              icon: Icons.account_balance_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppStatCard(
              title: 'Monthly EMI',
              value: loan.monthlyEmi.currency,
              icon: Icons.request_quote),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppStatCard(
              title: 'Outstanding',
              value: loan.outstandingAmount.currency,
              icon: Icons.hourglass_bottom,
              color: loan.outstandingAmount > 0
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF16A34A)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppStatCard(
              title: 'Paid / Total',
              value: '${controller.paidCount}/${loan.tenureMonths} EMIs',
  caption: '₹${AppFormatters.amount(controller.totalPaid)}',
              icon: Icons.check_circle_outline,
              color: const Color(0xFF16A34A)),
        ),
      ],
    );
  }
}

class _Schedule extends GetView<LoanDetailsController> {
  @override
  Widget build(BuildContext context) {
    final LoanModel loan = controller.loan.value!;
    return AppCard(
      title: 'EMI Schedule',
      actions: <Widget>[
        TextButton(
          onPressed: () => _receipt(context),
          child: const Text('PDF'),
        ),
      ],
      child: Obx(
        () => AppTable<EmiScheduleModel>(
          items: controller.schedule.value,
          keyOf: (EmiScheduleModel r) => '${r.loanId}-${r.installmentNo}',
          info: const PageInfo(page: 1, pageSize: 100, total: 100),
          isLoading: false,
          onRefresh: () => controller.load(loan.id!),
          emptyTitle: 'Schedule not generated',
          columns: <AppColumn<EmiScheduleModel>>[
            AppColumn(
              label: '#',
              numeric: true,
              value: (EmiScheduleModel r) =>
                  TableCells.text('${r.installmentNo}', bold: true),
            ),
            AppColumn(
              label: 'Due Date',
              value: (EmiScheduleModel r) =>
                  TableCells.text(AppFormatters.date(r.dueDate)),
            ),
            AppColumn(
              label: 'EMI',
              numeric: true,
              value: (EmiScheduleModel r) =>
                  TableCells.text(r.emiAmount.currency),
            ),
            AppColumn(
              label: 'Principal',
              numeric: true,
              value: (EmiScheduleModel r) =>
                  TableCells.text(r.principalPart.currency),
            ),
            AppColumn(
              label: 'Interest',
              numeric: true,
              value: (EmiScheduleModel r) =>
                  TableCells.text(r.interestPart.currency),
            ),
            AppColumn(
              label: 'Balance',
              numeric: true,
              value: (EmiScheduleModel r) =>
                  TableCells.text(r.balanceAfter.currency),
            ),
            AppColumn(
              label: 'Status',
              value: (EmiScheduleModel r) =>
                  AppStatusChip(status: r.status),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _receipt(BuildContext context) async {
    final LoanModel loan = controller.loan.value!;
    final PdfService pdf = Get.find<PdfService>();
    try {
      final String path = await pdf.reportPdf(
        title: 'EMI Statement — ${loan.loanNumber}',
        columns: const <String>[
          'No',
          'Due',
          'EMI',
          'Principal',
          'Interest',
          'Balance',
          'Status'
        ],
        rows: <List<String>>[
          for (final EmiScheduleModel r in controller.schedule.value)
            <String>[
              '${r.installmentNo}',
              AppFormatters.date(r.dueDate),
              AppFormatters.amount(r.emiAmount),
              AppFormatters.amount(r.principalPart),
              AppFormatters.amount(r.interestPart),
              AppFormatters.amount(r.balanceAfter),
              AppFormatters.humanize(r.status),
            ],
        ],
      ).then((bytes) => pdf.savePdf(bytes,
          filename: '${loan.loanNumber}-emi-statement.pdf'));
      AppSnackbar.success(context, 'Saved to $path');
    } catch (e) {
      AppSnackbar.error(context, 'Could not generate statement');
    }
  }
}
