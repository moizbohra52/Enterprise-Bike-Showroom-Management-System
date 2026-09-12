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
import 'package:enterprise_bike_showroom/features/payments/controllers/payment_controller.dart';
import 'package:enterprise_bike_showroom/features/payments/models/payment_models.dart';
import 'package:enterprise_bike_showroom/services/pdf_service.dart';

/// Payment details + refund + receipt.
class PaymentDetailsView extends GetView<PaymentDetailsController> {
  const PaymentDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Payment', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Payment Details',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final PaymentModel? payment = controller.payment.value;
          if (payment == null || payment.refunded) {
            return const SizedBox.shrink();
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppButton(
                label: 'Receipt',
                icon: Icons.receipt_long,
                variant: AppButtonVariant.outlined,
                onPressed: () => _receipt(payment),
              ),
              const SizedBox(width: 8),
              if (session.can(Permissions.paymentsCancel))
                AppButton(
                  label: 'Refund',
                  icon: Icons.undo,
                  variant: AppButtonVariant.error,
                  onPressed: () => _confirmRefund(payment),
                ),
            ],
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.payment.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(controller.payment.value!),
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

  Future<void> _receipt(PaymentModel payment) async {
    final PdfService pdf = Get.find<PdfService>();
    try {
      final String path = await pdf.paymentReceiptPdf(PaymentReceiptData(
        paymentNumber: payment.paymentNumber,
        paymentDate: payment.paymentDate ?? DateTime.now(),
        amount: payment.amount,
        method: AppFormatters.humanize(payment.paymentMode),
        referenceNumber: payment.referenceNumber ?? '-',
        customerName: payment.customerName,
      )).then((bytes) => pdf.savePdf(bytes,
          filename: '${payment.paymentNumber}.pdf'));
      AppSnackbar.success(context, 'Saved to $path');
    } catch (e) {
      AppSnackbar.error(context, 'Could not generate receipt');
    }
  }

  Future<void> _confirmRefund(PaymentModel payment) async {
    final String? reason = await AppDialog.prompt(
      context,
      title: 'Refund ${payment.paymentNumber}',
      message: 'The payment of ${payment.amount.currency} will be voided '
          'and the invoice balance restored. Reason:',
      confirmLabel: 'Refund Payment',
      errorLabel: 'The customer will be owed this amount again.',
    );
    if (reason == null || reason.trim().isEmpty) return;
    final bool ok = await controller.refund(reason.trim());
    if (ok) AppSnackbar.success(context, 'Payment refunded');
  }

  Widget _body(PaymentModel payment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(payment.paymentNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${AppFormatters.date(payment.paymentDate)} · '
                    '${payment.customerName} · '
                    '${AppFormatters.humanize(payment.paymentMode)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(
                status: payment.refunded ? 'refunded' : payment.status),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Amount',
                  value: payment.amount.currency,
                  icon: Icons.payments_outlined,
                  color: payment.refunded
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Reference',
                  value: payment.referenceNumber ?? '-',
                  icon: Icons.qr_code_2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Type',
                  value: payment.isDownPayment
                      ? 'Down Payment'
                      : payment.isEmi
                          ? 'EMI'
                          : 'Regular',
                  icon: Icons.category_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _row('Received by', payment.receivedBy ?? '-'),
              _row('Notes', payment.notes ?? '-'),
              if (payment.refunded) ...<Widget>[
                _row('Refund reason', payment.refundReason ?? '-'),
                _row('Refunded at', AppFormatters.dateTime(payment.refundedAt)),
              ],
              _row('Recorded', AppFormatters.dateTime(payment.createdAt)),
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
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
