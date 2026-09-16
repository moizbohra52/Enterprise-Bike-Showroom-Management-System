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
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/expenses/controllers/expense_controller.dart';
import 'package:enterprise_bike_showroom/features/expenses/models/expense_models.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Expense details + approve / reject (workflow).
class ExpenseDetailsView extends GetView<ExpenseDetailsController> {
  const ExpenseDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Expense', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Expense Details',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final ExpenseModel? expense = controller.expense.value;
          if (expense == null || expense.status != 'pending') {
            return const SizedBox.shrink();
          }
          if (!session.can(Permissions.expensesApprove)) {
            return const SizedBox.shrink();
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppButton(
                label: 'Reject',
                icon: Icons.cancel_outlined,
                variant: AppButtonVariant.danger,
                onPressed: () => _reject(context),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Approve',
                icon: Icons.check_circle_outline,
                onPressed: () => _approve(context),
              ),
            ],
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.expense.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(context, controller.expense.value!),
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

  Future<void> _approve(BuildContext context) async {
    final bool ok = await controller.approve();
    if (ok) AppSnackbar.success(context, 'Expense approved');
  }

  Future<void> _reject(BuildContext context) async {
    final String? reason = await AppDialog.prompt(
      context,
      title: 'Reject expense',
      message: 'Enter the reason for rejection:',
      confirmLabel: 'Reject',
    );
    if (reason == null) return;
    final bool ok = await controller.reject(reason);
    if (ok) AppSnackbar.success(context, 'Expense rejected');
  }

  Widget _body(BuildContext context, ExpenseModel expense) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(expense.expenseNumber.isEmpty
                      ? expense.description
                      : expense.expenseNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${expense.categoryLabel} · '
                    '${AppFormatters.date(expense.date)} · '
                    '${AppFormatters.humanize(expense.paymentMode)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(status: expense.status),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Amount',
                  value: expense.amount.currency,
                  icon: Icons.payments_outlined,
                  color: const Color(0xFFDC2626)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Voucher',
                  value:
                      expense.voucherNumber.isEmpty ? '-' : expense.voucherNumber,
                  icon: Icons.description_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Reference',
                  value:
                      expense.referenceNumber.isEmpty ? '-' : expense.referenceNumber,
                  icon: Icons.qr_code_2),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _row('Description', expense.description),
              _row('Notes', expense.notes.isEmpty ? '-' : expense.notes),
              if (expense.status == 'approved') ...<Widget>[
                _row('Approved by', expense.approvedBy ?? '-'),
                _row(
                    'Approved at', AppFormatters.dateTime(expense.approvedAt)),
              ],
              if (expense.status == 'rejected') ...<Widget>[
                _row('Rejected by', expense.rejectedBy ?? '-'),
                _row('Reason', expense.rejectionReason ?? '-'),
              ],
              _row('Created', AppFormatters.dateTime(expense.createdAt)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
