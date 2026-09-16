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
import 'package:enterprise_bike_showroom/features/purchases/controllers/purchase_controller.dart';
import 'package:enterprise_bike_showroom/features/purchases/models/purchase_models.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Purchase details: lines + receive + pay supplier.
class PurchaseDetailsView extends GetView<PurchaseDetailsController> {
  const PurchaseDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Purchase', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Purchase Details',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final PurchaseModel? purchase = controller.purchase.value;
          if (purchase == null) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (session.can(Permissions.purchasesEdit) &&
                  purchase.status != 'received' &&
                  purchase.status != 'cancelled')
                AppButton(
                  label: 'Receive Stock',
                  icon: Icons.inventory_2_outlined,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => _receive(context),
                ),
              if (session.can(Permissions.purchasesEdit) &&
                  purchase.outstandingAmount > 0) ...<Widget>[
                const SizedBox(width: 8),
                AppButton(
                  label: 'Pay Supplier',
                  icon: Icons.payments_outlined,
                  onPressed: () => _pay(context),
                ),
              ],
            ],
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.purchase.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(context, controller.purchase.value!),
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

  Future<void> _receive(BuildContext context) async {
    final PurchaseModel purchase = controller.purchase.value!;
    final bool confirmed = await AppDialog.confirm(
      context,
      title: 'Receive stock',
      message: 'Mark ${purchase.purchaseNumber} as received? Stock will be '
          'added to inventory and accounting updated.',
      confirmLabel: 'Receive',
    );
    if (!confirmed) return;
    final bool ok = await controller.receive();
    if (ok) AppSnackbar.success(context, 'Stock received');
  }

  Future<void> _pay(BuildContext context) async {
    final PurchaseModel purchase = controller.purchase.value!;
    final num outstanding = purchase.outstandingAmount;
    final String? raw = await AppDialog.prompt(
      context,
      title: 'Pay supplier',
      message: 'Outstanding: ${AppFormatters.currency(outstanding)}\n'
          'Enter amount to pay (full amount to settle).',
      confirmLabel: 'Pay',
    );
    if (raw == null) return;
    final num amount = double.tryParse(raw) ?? 0;
    if (amount <= 0 || amount > outstanding) {
      AppSnackbar.error(context, 'Enter an amount between 0 and $outstanding');
      return;
    }
    final String? mode = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('Payment mode'),
        children: <Widget>[
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'cash'),
              child: const Text('Cash')),
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'bank_transfer'),
              child: const Text('Bank Transfer')),
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'cheque'),
              child: const Text('Cheque')),
          SimpleDialogOption(
              onPressed: () => Get.back(result: 'upi'),
              child: const Text('UPI')),
        ],
      ),
    );
    if (mode == null) return;
    final bool ok = await controller.pay(amount, mode);
    if (ok) AppSnackbar.success(context, 'Payment recorded');
  }

  Widget _body(BuildContext context, PurchaseModel purchase) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(purchase.purchaseNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${purchase.supplierName} · Ordered '
                    '${AppFormatters.date(purchase.orderDate)} · Expected '
                    '${AppFormatters.date(purchase.expectedDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(status: purchase.status),
            const SizedBox(width: 8),
            AppStatusChip(status: purchase.paymentStatus),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Total',
                  value: purchase.totalAmount.currency,
                  icon: Icons.shopping_cart_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Paid',
                  value: purchase.paidAmount.currency,
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Outstanding',
                  value: purchase.outstandingAmount.currency,
                  icon: Icons.hourglass_bottom,
                  color: purchase.outstandingAmount > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Received',
                  value: '${purchase.totalReceived.asInt}/${purchase.lines.fold<num>(0, (num s, PurchaseLineModel l) => s + l.qty).asInt} units',
                  icon: Icons.inventory_2_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Lines',
          child: Column(
            children: <Widget>[
              for (final PurchaseLineModel line in purchase.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${line.lineNumber}. ${line.productName}'
                          '${line.color.isNotEmpty ? ' (${line.color})' : ''}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text('${line.qty} × ${line.unitCost.currency}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 24),
                      Text('${line.receivedQty.asInt} received',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF64748B))),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 110,
                        child: Text(line.totalAmount.currency,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 16),
              _sum('Subtotal', purchase.subtotal.currency),
              _sum('Tax', purchase.taxAmount.currency),
              _sum('Discount', '-${purchase.discountAmount.currency}'),
              _sum('Total', purchase.totalAmount.currency, bold: true),
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
