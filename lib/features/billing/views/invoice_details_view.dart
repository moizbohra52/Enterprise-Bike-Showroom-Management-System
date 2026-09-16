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
import 'package:enterprise_bike_showroom/features/billing/controllers/invoice_controller.dart';
import 'package:enterprise_bike_showroom/features/billing/models/invoice_models.dart';
import 'package:enterprise_bike_showroom/services/pdf_service.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Invoice document: lines, totals, payment history, PDF, void.
class InvoiceDetailsView extends GetView<InvoiceDetailsController> {
  const InvoiceDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Invoice', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Invoice',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final InvoiceModel? invoice = controller.invoice.value;
          if (invoice == null) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppButton(
                label: 'PDF',
                icon: Icons.picture_as_pdf,
                variant: AppButtonVariant.outlined,
                onPressed: () => _downloadPdf(context, invoice),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Print',
                icon: Icons.print_outlined,
                variant: AppButtonVariant.outlined,
                onPressed: () => _printPdf(context, invoice),
              ),
              const SizedBox(width: 8),
              if (session.can(Permissions.paymentsCreate) &&
                  invoice.outstandingAmount > 0 &&
                  invoice.status != 'void')
                AppButton(
                  label: 'Receive Payment',
                  icon: Icons.payments_outlined,
                  onPressed: () => _paySheet(context, invoice),
                ),
            ],
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.invoice.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(context, controller.invoice.value!),
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

  Future<void> _downloadPdf(BuildContext context, InvoiceModel invoice) async {
    final PdfService pdf = Get.find<PdfService>();
    try {
      final String path = await pdf.invoicePdf(_data(invoice)).then(
          (bytes) => pdf.savePdf(bytes,
              filename: '${invoice.invoiceNumber}.pdf'));
      AppSnackbar.success(context, 'Saved to $path');
    } catch (e) {
      AppSnackbar.error(context, 'Could not generate PDF');
    }
  }

  Future<void> _printPdf(BuildContext context, InvoiceModel invoice) async {
    final PdfService pdf = Get.find<PdfService>();
    try {
      await pdf.invoicePdf(_data(invoice)).then(
          (bytes) => pdf.printPdf(bytes,
              filename: '${invoice.invoiceNumber}.pdf'));
    } catch (e) {
      AppSnackbar.error(context, 'Could not print');
    }
  }

  InvoicePdfData _data(InvoiceModel invoice) {
    return InvoicePdfData(
      invoiceNumber: invoice.invoiceNumber,
      invoiceDate: invoice.invoiceDate ?? DateTime.now(),
      invoiceType: 'SALE INVOICE',
      customerName: invoice.customerName,
      customerPhone: '',
      items: <InvoicePdfItem>[
        for (final InvoiceLineItemModel item in invoice.lineItems)
          InvoicePdfItem(
            description: item.description,
            quantity: item.qty,
            unitPrice: item.unitPrice,
            discount: item.discount,
            taxRate: item.taxRate,
            totalAmount: item.totalAmount,
          ),
      ],
      subtotal: invoice.subtotal,
      discount: invoice.discountAmount,
      taxAmount: invoice.taxAmount,
      totalAmount: invoice.totalAmount,
      paidAmount: invoice.paidAmount,
      outstandingAmount: invoice.outstandingAmount,
      status: invoice.status.toUpperCase(),
      notes: invoice.notes,
    );
  }

  Future<void> _paySheet(BuildContext context, InvoiceModel invoice) async {
    final num outstanding = invoice.outstandingAmount;
    final String? reference = await AppDialog.prompt(
      context,
      title: 'Receive Payment',
      message:
          'Outstanding on ${invoice.invoiceNumber}: $outstanding',
      confirmLabel: 'Record Payment',
    );
    if (reference == null) return;
    final num amount = double.tryParse(reference) ?? 0;
    if (amount <= 0 || amount > outstanding) {
      AppSnackbar.error(context, 'Enter an amount between 0 and $outstanding');
      return;
    }
    final String? mode = await _pickMode(context);
    if (mode == null) return;
    final bool ok =
        await controller.pay(amount: amount, paymentMode: mode);
    if (ok) AppSnackbar.success(context, 'Payment recorded');
  }

  Future<String?> _pickMode(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Payment mode'),
        children: <Widget>[
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'cash'),
              child: const Text('Cash')),
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'upi'), child: const Text('UPI')),
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'card'),
              child: const Text('Card')),
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'cheque'),
              child: const Text('Cheque')),
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'bank_transfer'),
              child: const Text('Bank Transfer')),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, InvoiceModel invoice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(invoice.invoiceNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${AppFormatters.date(invoice.invoiceDate)}  ·  '
                    '${invoice.customerName}  ·  '
                    'Due ${AppFormatters.date(invoice.dueDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(status: invoice.status),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Total',
                  value: invoice.totalAmount.currency,
                  icon: Icons.receipt_long),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Paid',
                  value: invoice.paidAmount.currency,
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Outstanding',
                  value: invoice.outstandingAmount.currency,
                  icon: Icons.hourglass_bottom,
                  color: invoice.outstandingAmount > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Items',
          child: Column(
            children: <Widget>[
              for (final InvoiceLineItemModel item in invoice.lineItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${item.lineNumber}. ${item.description}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                          '${item.qty} × ${item.unitPrice.currency}'
                          '${item.taxRate > 0 ? ' @ ${item.taxRate.toStringAsFixed(0)}% tax' : ''}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 110,
                        child: Text(item.totalAmount.currency,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 16),
              _sum('Subtotal', invoice.subtotal.currency),
              _sum('Discount', '-${invoice.discountAmount.currency}'),
              _sum('Tax (${invoice.taxRate.toStringAsFixed(0)}%)',
                  invoice.taxAmount.currency),
              _sum('Total', invoice.totalAmount.currency, bold: true),
              if (invoice.status == 'void') ...<Widget>[
                const Divider(height: 16),
                Text(
                  'VOID — ${invoice.voidReason ?? ''} '
                  '(${AppFormatters.date(invoice.voidedAt)})',
                  style: const TextStyle(
                      color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final List<Map<String, dynamic>> payments = controller.payments.value;
          return AppCard(
            title: 'Payments',
            child: payments.isEmpty
                ? const Text('No payments yet.',
                    style:
                        TextStyle(color: Color(0xFF64748B), fontSize: 13))
                : Column(
                    children: <Widget>[
                      for (final Map<String, dynamic> p in payments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '${p['payment_number'] ?? 'Payment'} — '
                                  '${AppFormatters.humanize(p['payment_mode']?.toString() ?? '')}',
                                  style:
                                      const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(AppFormatters.date(p['payment_date']),
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
                              const SizedBox(width: 24),
                              Text(
                                  AppFormatters.currency(double.tryParse(p['amount']?.toString() ?? '') ?? 0),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
          );
        }),
      ],
    );
  }

  Widget _sum(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
