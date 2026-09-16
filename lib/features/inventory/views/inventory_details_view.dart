import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dialog.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/inventory/controllers/inventory_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/models/inventory_models.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Single-bike details + status actions + stock history.
class InventoryDetailsView extends GetView<InventoryDetailsController> {
  const InventoryDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'];
    if (id == null) {
      return AppShell(
          title: 'Inventory', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));

    return AppShell(
      title: 'Inventory Details',
      showBack: true,
      actions: <Widget>[
        AppButton(
          label: 'Adjust Status',
          icon: Icons.edit_note,
          variant: AppButtonVariant.outlined,
          onPressed: () => _pickStatus(context),
        ),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.inventory.value == null) {
          return const AppLoader();
        }
        final InventoryModel item = controller.inventory.value!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppCard(
                title: item.productLabel,
                subtitle: item.colorLabel,
                actions: <Widget>[AppStatusChip(status: item.status)],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _row('Stock Code', item.stockCode, bold: true),
                    _row('Chassis Number', item.chassisNumber),
                    _row('Engine Number', item.engineNumber),
                    _row('Model Year', item.modelYear?.toString() ?? '-'),
                    _row('Manufacturing Date', AppFormatters.date(item.manufacturingDate)),
                    _row('Purchase Date', AppFormatters.date(item.purchaseDate)),
                    _row('Purchase Price', item.purchasePrice.currency),
                    _row('Location', item.location),
                    _row('Added', AppFormatters.date(item.createdAt)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Stock History',
                child: controller.history.value.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No movements recorded yet.'),
                      )
                    : Column(
                        children: <Widget>[
                          for (final StockHistoryModel h in controller.history.value)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: <Widget>[
                                  AppStatusChip(
                                    status: h.toStatus ?? 'active',
                                    label: h.action,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      h.notes.isEmpty
                                          ? h.action
                                          : h.notes,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                  Text(
                                    AppFormatters.date(h.createdAt),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _pickStatus(BuildContext context) async {
    final String? status = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('Change status'),
        children: const <Widget>[
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'available'), child: Text('Available')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'reserved'), child: Text('Reserved')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'demo'), child: Text('Demo')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'damaged'), child: Text('Damaged')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'returned'), child: Text('Returned')),
        ],
      ),
    );
    if (status == null) return;
    final bool ok = await controller.changeStatus(status);
    if (ok) {
      AppSnackbar.success(context, 'Status updated');
      final InventoryController list = Get.find<InventoryController>();
      list.refresh();
    } else {
      AppSnackbar.error(context, 'Could not update status.');
    }
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}
