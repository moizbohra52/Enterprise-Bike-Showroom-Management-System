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
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/sales/controllers/sale_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// The new-sale flow: customer → vehicle → extras → payment → delivery.
class SaleFormView extends GetView<SaleFormController> {
  const SaleFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? preCustomer = Get.parameters['customerId'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.init(customerId: preCustomer);
    });

    return AppShell(
      title: 'New Sale',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Complete Sale',
            icon: Icons.check_circle_outline,
            isLoading: controller.saving.value,
            onPressed: () => _submit(context),
          ),
        ),
      ],
      child: Obx(() {
        if (controller.error.value.isNotEmpty) {
          return _errorState();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CustomerSection(),
              const SizedBox(height: 12),
              _VehicleSection(),
              const SizedBox(height: 12),
              if (controller.selectedVehicleId.value != null) ...<Widget>[
                _AccessoriesSection(),
                const SizedBox(height: 12),
              ],
              _PaymentSection(),
              const SizedBox(height: 12),
              _TotalsSection(),
              const SizedBox(height: 12),
              _DeliverySection(),
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 42, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text(controller.error.value,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14)),
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

  Future<void> _submit(BuildContext context) async {
    final bool ok = await controller.submit(delivery: controller.buildDelivery());
    if (ok) {
      AppSnackbar.success(context, 'Sale completed');
      Get.until((route) => route.settings.name == AppRoutes.sales);
    }
  }
}

class _CustomerSection extends GetView<SaleFormController> {
  @override
  Widget build(BuildContext context) {
    final List<DropdownOption<String>> options = <DropdownOption<String>>[
      for (final Map<String, dynamic> c in controller.customers.value)
        DropdownOption<String>(
          value: SafeJson.asId(c['id']) ?? '',
          label:
              '${c['name'] ?? ''} · ${c['phone'] ?? ''} · ${c['customer_code'] ?? ''}',
        ),
    ];
    return AppCard(
      title: 'Customer',
      child: Column(
        children: <Widget>[
          AppTextField(
            label: 'Search customer (name / phone / code)',
            controller: _search,
            onChanged: (String value) => controller.customerSearch.value = value,
          ),
          const SizedBox(height: 12),
          AppDropdown<String?>(
            label: 'Select customer',
            options: options,
            value: controller.customerId.value,
            onChanged: (String? value) =>
                value != null && value.isNotEmpty ? controller.selectCustomer(value) : null,
          ),
          TextButton(
            onPressed: () async {
              await Get.toNamed(AppRoutes.customerForm);
              await controller.loadCustomers();
            },
            child: const Text('Add new customer'),
          ),
        ],
      ),
    );
  }

  final TextEditingController _search = TextEditingController();
}

class _VehicleSection extends GetView<SaleFormController> {
  @override
  Widget build(BuildContext context) {
    final List<DropdownOption<String>> options = <DropdownOption<String>>[
      for (final Map<String, dynamic> v in controller.availableVehicles.value)
        DropdownOption<String>(
          value: SafeJson.asId(v['id']) ?? '',
          label: _label(v),
        ),
    ];
    return AppCard(
      title: 'Vehicle (from showroom stock)',
      child: Column(
        children: <Widget>[
          AppDropdown<String?>(
            label: controller.customerId.value == null
                ? 'Select a customer first'
                : 'Select vehicle',
            options: options,
            value: controller.selectedVehicleId.value,
            onChanged: (String? value) => value != null && value.isNotEmpty
                ? controller.selectVehicle(value)
                : null,
          ),
          if (controller.availableVehicles.value.isEmpty &&
              controller.customerId.value != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No available stock. Add stock via Inventory first.',
                  style: TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
            ),
        ],
      ),
    );
  }

  String _label(Map<String, dynamic> v) {
    final dynamic product = v['product'];
    final Map<String, dynamic> pm =
        product is Map ? SafeJson.asMap(product) : <String, dynamic>{};
    final dynamic colors = pm['colors'];
    String color = '';
    if (colors is List && colors.isNotEmpty) {
      final dynamic first = colors.first;
      if (first is Map) color = SafeJson.asText(SafeJson.asMap(first)['name']);
    }
    final dynamic brand = pm['brand'];
    final String brandName =
        brand is Map ? SafeJson.asText(SafeJson.asMap(brand)['name']) : '';
    return [
      if (brandName.isNotEmpty) brandName,
      SafeJson.asText(pm['name']),
      SafeJson.asText(pm['model']),
      if (color.isNotEmpty) color,
      'Chassis ${SafeJson.asText(v['chassis_number'])}',
      SafeJson.asMoney(pm['mrp_price']).currency,
    ].join(' · ');
  }
}

class _AccessoriesSection extends GetView<SaleFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Accessories & Add-ons',
      child: controller.accessories.value.isEmpty
          ? const Text('No accessories configured for this model.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13))
          : Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                for (final Map<String, dynamic> row in controller.accessories.value)
                  _AccessoryChip(row: row),
              ],
            ),
    );
  }
}

class _AccessoryChip extends GetView<SaleFormController> {
  const _AccessoryChip({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final String? id = SafeJson.asId(row['id']);
    final dynamic accProduct = row['accessory'];
    final Map<String, dynamic> am =
        accProduct is Map ? SafeJson.asMap(accProduct) : <String, dynamic>{};
    final String name = SafeJson.asText(am['name']);
    final String price = SafeJson.asMoney(am['mrp_price']).currency;
    final int qty = id == null ? 0 : (controller.accessoryQty[id] ?? 0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
            color: qty > 0
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Expanded(
            child: Text('$name · $price',
                style: const TextStyle(fontSize: 13)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            onPressed: id != null && qty > 0
                ? () => controller.setAccessoryQty(id, qty - 1)
                : null,
          ),
          Text('$qty',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            onPressed: id != null
                ? () => controller.setAccessoryQty(id, qty + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

class _PaymentSection extends GetView<SaleFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Payment',
      child: Column(
        children: <Widget>[
          RadioListTile<String>(
            title: const Text('Full payment (Cash / UPI / Card / Cheque / Bank)'),
            value: 'cash',
            groupValue: controller.paymentMode.value,
            onChanged: controller.changePaymentMode,
            dense: true,
          ),
          RadioListTile<String>(
            title: const Text('EMI (down payment now, rest in installments)'),
            value: 'emi',
            groupValue: controller.paymentMode.value,
            onChanged: controller.changePaymentMode,
            dense: true,
          ),
          if (controller.isEmi) ...<Widget>[
            AppDropdown<String?>(
              label: 'EMI plan',
              options: <DropdownOption<String>>[
                for (final Map<String, dynamic> plan in controller.emiPlans.value)
                  DropdownOption<String>(
                    value: SafeJson.asId(plan['id']) ?? '',
                    label: '${SafeJson.asText(plan['name'])} — '
                        '${SafeJson.asText(plan['interest_rate'])}% '
                        '(${SafeJson.asText(plan['method'])})',
                  ),
              ],
              value: controller.emiPlanId.value,
              onChanged: (String? value) {
                controller.emiPlanId.value = value;
                controller.changePaymentMode(controller.paymentMode.value);
              },
            ),
            AppTextField(
              label: 'Down payment',
              keyboardType: TextInputType.number,
              initialValue: controller.downPayment.value.toStringAsFixed(0),
              onChanged: (String value) => controller.downPayment.value =
                  double.tryParse(value) ?? 0,
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppTextField(
                    label: 'Tenure (months)',
                    keyboardType: TextInputType.number,
                    initialValue: '${controller.tenure.value}',
                    onChanged: (String value) =>
                        controller.tenure.value = int.tryParse(value) ?? 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalsSection extends GetView<SaleFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Totals',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _row('Vehicle', controller.vehiclePrice.value.currency),
          _row('Accessories', controller.accessoriesTotal.value.currency),
          _row('Discount',
              '-${controller.discount.value.currency}',
              trailing: _discountField()),
          _row('Tax (${controller.taxRate.toStringAsFixed(0)}%)',
              controller.taxAmount.value.currency),
          const Divider(height: 16),
          _row('Total', controller.total.value.currency,
              bold: true, size: 16),
          if (controller.isEmi) ...<Widget>[
            _row('Down payment', controller.downPayment.value.currency),
            _row('Loan amount', controller.loanAmount.value.currency),
            _row(
                'Monthly EMI (${controller.tenure.value} mo)',
                '${controller.monthlyEmi.value.currency} / month'),
            _row('Total of EMIs', controller.totalEmi.value.currency),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, double size = 14, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: size - 1,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
          if (trailing != null) trailing,
          Text(value,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _discountField() {
    return SizedBox(
      width: 110,
      child: TextField(
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          border: OutlineInputBorder(),
          prefixText: '₹ ',
        ),
        onChanged: (String value) =>
            controller.discount.value = double.tryParse(value) ?? 0,
      ),
    );
  }
}

class _DeliverySection extends StatefulWidget {
  const _DeliverySection();

  @override
  State<_DeliverySection> createState() => _DeliverySectionState();
}

class _DeliverySectionState extends State<_DeliverySection> {
  bool _expanded = false;
  final TextEditingController _odometer = TextEditingController();
  final TextEditingController _registration = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final SaleFormController controller = Get.find<SaleFormController>();
    if (!_odometer.text.isEmpty && controller.odometer.value.isEmpty) {
      // keep in sync after rebuilds
      controller.odometer.value = _odometer.text;
      controller.registration.value = _registration.text;
    }
    return AppCard(
      title: 'Delivery (optional — can be completed later)',
      actions: <Widget>[
        Checkbox(
          value: _expanded,
          onChanged: (bool? value) {
            setState(() => _expanded = value ?? false);
            controller.deliveryEnabled.value = _expanded;
          },
        ),
      ],
      child: _expanded
          ? Column(
              children: <Widget>[
                AppDatePicker(
                  label: 'Delivery date',
                  value: controller.deliveryDate.value,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                  onChanged: (DateTime? value) =>
                      controller.deliveryDate.value = value,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _odometer,
                  keyboardType: TextInputType.number,
                  onChanged: (String value) =>
                      controller.odometer.value = value,
                  decoration: const InputDecoration(
                      labelText: 'Odometer at delivery (km)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _registration,
                  onChanged: (String value) =>
                      controller.registration.value = value,
                  decoration: const InputDecoration(
                      labelText: 'Registration number (optional now)'),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
