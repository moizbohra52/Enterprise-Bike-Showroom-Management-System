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
import 'package:enterprise_bike_showroom/features/sales/controllers/sale_controller.dart';
import 'package:enterprise_bike_showroom/features/sales/models/sale_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Sale details: lines, totals, invoice + payments, actions.
class SaleDetailsView extends GetView<SaleDetailsController> {
  const SaleDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Sale', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Sale Details',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final SaleModel? sale = controller.sale.value;
          if (sale == null) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (session.can(Permissions.paymentsCreate) &&
                  sale.balanceAmount > 0 &&
                  sale.invoiceId != null)
                AppButton(
                  label: 'Receive Payment',
                  icon: Icons.payments_outlined,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => Get.toNamed(AppRoutes.paymentForm,
                      parameters: <String, String>{'invoiceId': sale.invoiceId!}),
                ),
              const SizedBox(width: 8),
              if (session.can(Permissions.salesCancel) &&
                  sale.status != 'cancelled' &&
                  sale.deliveryDate == null)
                AppButton(
                  label: 'Cancel Sale',
                  icon: Icons.cancel_outlined,
                  variant: AppButtonVariant.danger,
                  onPressed: () => _confirmCancel(context, sale),
                ),
            ],
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.sale.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(context, controller.sale.value!),
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

  Future<void> _confirmCancel(BuildContext context, SaleModel sale) async {
    final String? reason = await AppDialog.prompt(
      context,
      title: 'Cancel Sale ${sale.saleNumber}',
      message: 'The sale will be cancelled, stock released and the invoice '
          'voided. Enter a reason:',
      confirmLabel: 'Cancel Sale',
      errorLabel: 'This action cannot be undone.',
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await controller.repository.cancel(sale.id!, reason.trim());
      AppSnackbar.success(context, 'Sale cancelled');
      Get.back();
    } catch (e) {
      AppSnackbar.error(context, e.toString());
    }
  }

  Widget _body(BuildContext context, SaleModel sale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(sale.saleNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${AppFormatters.date(sale.saleDate)}  ·  '
                    '${sale.customerName}  ·  '
                    'Type: ${AppFormatters.humanize(sale.saleType)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(status: sale.status),
            const SizedBox(width: 8),
            if (sale.emi)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('EMI',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Total',
                  value: sale.totalAmount.currency,
                  icon: Icons.account_balance_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Paid',
                  value: sale.paidAmount.currency,
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Balance',
                  value: sale.balanceAmount.currency,
                  icon: Icons.hourglass_bottom,
                  color: sale.balanceAmount > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Invoice',
                  value: sale.invoiceNumber ?? '-',
                  icon: Icons.receipt_long,
  caption:
                      sale.invoiceStatus == null ? '' : AppFormatters.humanize(sale.invoiceStatus!)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Items',
          child: Column(
            children: <Widget>[
              for (final SaleLineItemModel item in sale.lineItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${item.lineNumber}. ${item.name}'
                          '${item.color == null || item.color!.isEmpty ? '' : ' (${item.color})'}'
                          '${item.chassisNumber == null || item.chassisNumber!.isEmpty ? '' : ' — ${item.chassisNumber}'}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text('${item.qty} × ${item.unitPrice.currency}',
                          style: Theme.of(context).textTheme.bodySmall),
                      SizedBox(width: 40, child: const SizedBox.shrink()),
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
              _sum('Subtotal', sale.subtotal.currency),
              _sum('Discount', '-${sale.discountAmount.currency}'),
              _sum('Tax', sale.taxAmount.currency),
              _sum('Total', sale.totalAmount.currency, bold: true),
              if (sale.deliveryDate != null) ...<Widget>[
                const Divider(height: 16),
                Text('Delivered ${AppFormatters.date(sale.deliveryDate)}',
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF16A34A))),
              ],
              if (sale.warrantyEnd != null)
                Text(
                    'Warranty until ${AppFormatters.date(sale.warrantyEnd)}',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
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
