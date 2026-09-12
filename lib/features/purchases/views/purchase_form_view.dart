import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_date_picker.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/purchases/controllers/purchase_controller.dart';
import 'package:enterprise_bike_showroom/features/products/models/product_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// New purchase order: supplier + lines + totals.
class PurchaseFormView extends GetView<PurchaseFormController> {
  const PurchaseFormView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.init();
    });

    return AppShell(
      title: 'New Purchase',
      showBack: true,
      actions: <Widget>[
        Obx(
          child: AppButton(
            label: 'Create Purchase',
            icon: Icons.check_circle_outline,
            isLoading: controller.saving,
            onPressed: () => _submit(),
          ),
        ),
      ],
      child: Obx(() {
        if (controller.error.value.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline,
                      size: 40, color: Color(0xFFDC2626)),
                  const SizedBox(height: 12),
                  Text(controller.error.value,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Retry',
                    variant: AppButtonVariant.outlined,
                    onPressed: () => controller.error.value = '',
                  ),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SupplierCard(),
              const SizedBox(height: 12),
              _LinesCard(),
              const SizedBox(height: 12),
              _TotalsCard(),
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _submit() async {
    final bool ok = await controller.submit();
    if (ok) {
      AppSnackbar.success(context, 'Purchase created');
      Get.until((route) => route.settings.name == AppRoutes.purchases);
    }
  }
}

class _SupplierCard extends GetView<PurchaseFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Supplier & Dates',
      child: Column(
        children: <Widget>[
          AppDropdown<String?>(
            label: 'Supplier',
            options: <DropdownOption<String>>[
              for (final Map<String, dynamic> s in controller.suppliers.value)
                DropdownOption<String>(
                  value: SafeJson.asId(s['id']) ?? '',
                  label: '${s['name'] ?? ''} · ${s['phone'] ?? ''}',
                ),
            ],
            value: controller.supplierId.value,
            onChanged: (String? value) =>
                controller.supplierId.value = value,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: AppDatePicker(
                  label: 'Order date',
                  value: controller.orderDate.value,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  onChanged: (DateTime? value) =>
                      controller.orderDate.value = value,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppDatePicker(
                  label: 'Expected delivery',
                  value: controller.expectedDate.value,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  onChanged: (DateTime? value) =>
                      controller.expectedDate.value = value,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinesCard extends GetView<PurchaseFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Lines',
      actions: <Widget>[
        AppButton(
          label: 'Add Line',
          icon: Icons.add,
          variant: AppButtonVariant.outlined,
          onPressed: _addLineSheet,
        ),
      ],
      child: Column(
        children: <Widget>[
          if (controller.lines.value.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No lines yet. Add products to buy.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            ),
          for (int i = 0; i < controller.lines.value.length; i++)
            _LineRow(index: i),
        ],
      ),
    );
  }

  Future<void> _addLineSheet() async {
    final List<ProductModel> products = controller.products.value;
    await showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      builder: (BuildContext context) => _AddLineSheet(
        products: products,
        onAdd: (ProductModel product) {
          controller.addLine(
            productId: product.id!,
            productName: product.name,
            unitCost: product.basePrice,
          );
        },
      ),
    );
  }
}

class _LineRow extends GetView<PurchaseFormController> {
  const _LineRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> line = controller.lines.value[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              '${line['product_name'] ?? 'Product'}'
              '${(line['color']?.toString() ?? '').isNotEmpty ? ' (${line['color']})' : ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(
            width: 70,
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Qty',
                contentPadding:
                    EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(
                  text: SafeJson.asMoney(line['qty']).toStringAsFixed(0)),
              onChanged: (String value) => controller.updateLine(
                  index, qty: double.tryParse(value) ?? 1),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Unit cost',
                contentPadding:
                    EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              controller: TextEditingController(
                  text: SafeJson.asMoney(line['unit_cost']).toStringAsFixed(0)),
              onChanged: (String value) => controller.updateLine(
                  index, unitCost: double.tryParse(value) ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              SafeJson.asMoney(line['qty']) *
                      SafeJson.asMoney(line['unit_cost']) ==
                  0
                  ? '₹ 0'
                  : '${(SafeJson.asMoney(line['qty']) * SafeJson.asMoney(line['unit_cost'])).currency}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: const Color(0xFFDC2626),
            onPressed: () => controller.removeLine(index),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends GetView<PurchaseFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Totals',
      child: Row(
        children: <Widget>[
          Expanded(
            child: AppTextField(
              label: 'Discount',
              keyboardType: TextInputType.number,
              onChanged: (String value) =>
                  controller.discount.value = double.tryParse(value) ?? 0,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppTextField(
              label: 'Notes',
              controller: _notes,
              onChanged: (String value) => controller.notes.value = value,
            ),
          ),
          const SizedBox(width: 12),
          Obx(
            child: SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('Total',
                      style:
                          Theme.of(context).textTheme.bodySmall),
                  Text(controller.total.value.currency,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  final TextEditingController _notes = TextEditingController();
}

class _AddLineSheet extends StatelessWidget {
  const _AddLineSheet({required this.products, required this.onAdd});

  final List<ProductModel> products;
  final void Function(ProductModel product) onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add line',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? const Center(
                      child: Text('No active products.',
                          style:
                              TextStyle(color: Color(0xFF64748B))))
                  : ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ProductModel product = products[index];
                        return ListTile(
                          title: Text(
                              '${product.name} ${product.model}'.trim()),
                          subtitle:
                              Text('Cost ${product.basePrice.currency}'),
                          onTap: () {
                            Get.back();
                            onAdd(product);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
