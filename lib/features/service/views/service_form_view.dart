import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/service/controllers/service_controller.dart';
import 'package:enterprise_bike_showroom/features/service/models/service_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// New job card: vehicle → items → open.
class ServiceFormView extends GetView<ServiceFormController> {
  const ServiceFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? vehicleParam = Get.parameters['vehicleId'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.init(vehicleId: vehicleParam);
    });

    return AppShell(
      title: 'New Job Card',
      showBack: true,
      actions: <Widget>[
        Obx(
          child: AppButton(
            label: 'Open Job Card',
            icon: Icons.check_circle_outline,
            isLoading: controller.saving,
            onPressed: () => _submit(),
          ),
        ),
      ],
      child: Obx(() {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (controller.error.value.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(controller.error.value,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFDC2626))),
                ),
              _VehicleCard(),
              const SizedBox(height: 12),
              _ItemsCard(),
              const SizedBox(height: 16),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _submit() async {
    final bool ok = await controller.submit();
    if (ok) {
      AppSnackbar.success(context, 'Job card opened');
      Get.until((route) => route.settings.name == AppRoutes.service);
    }
  }
}

class _VehicleCard extends GetView<ServiceFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Customer & Vehicle',
      child: Column(
        children: <Widget>[
          AppDropdown<String?>(
            label: 'Customer',
            options: <DropdownOption<String>>[
              for (final Map<String, dynamic> c in controller.customers.value)
                DropdownOption<String>(
                  value: SafeJson.asId(c['id']) ?? '',
                  label: '${c['name'] ?? ''} · ${c['phone'] ?? ''}',
                ),
            ],
            value: controller.customerId.value,
            onChanged: (String? value) =>
                value != null && value.isNotEmpty
                    ? controller.selectCustomer(value)
                    : null,
          ),
          const SizedBox(height: 12),
          AppDropdown<String?>(
            label: 'Vehicle',
            options: <DropdownOption<String>>[
              for (final Map<String, dynamic> v in controller.vehicles.value)
                DropdownOption<String>(
                  value: SafeJson.asId(v['id']) ?? '',
                  label: '${v['registration_number'] ?? ''} · '
                      '${v['chassis_number'] ?? ''}',
                ),
            ],
            value: controller.vehicleId.value,
            onChanged: (String? value) =>
                value != null && value.isNotEmpty
                    ? controller.selectVehicle(value)
                    : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  label: 'Odometer in (km)',
                  keyboardType: TextInputType.number,
                  initialValue:
                      controller.odometerIn.value > 0 ? controller.odometerIn.value.toStringAsFixed(0) : '',
                  onChanged: (String value) => controller.odometerIn.value =
                      double.tryParse(value) ?? 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppDropdown<String>(
                  label: 'Job type',
                  options: const <DropdownOption<String>>[
                    DropdownOption(value: 'paid', label: 'Paid'),
                    DropdownOption(value: 'free', label: 'Free (plan)'),
                    DropdownOption(value: 'warranty', label: 'Warranty'),
                  ],
                  value: controller.jobType.value,
                  onChanged: (String? value) =>
                      controller.jobType.value = value ?? 'paid',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Problem reported by customer',
            maxLines: 3,
            onChanged: (String value) => controller.problem.value = value,
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends GetView<ServiceFormController> {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Items (parts & labour)',
      actions: <Widget>[
        AppButton(
          label: 'Add Item',
          icon: Icons.add,
          variant: AppButtonVariant.outlined,
          onPressed: _addItemSheet,
        ),
      ],
      child: Column(
        children: <Widget>[
          if (controller.items.value.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No items yet.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            ),
          for (int i = 0; i < controller.items.value.length; i++)
            _ItemRow(index: i),
          if (controller.items.value.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Total: ${controller.total.value.currency}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addItemSheet() async {
    await showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      builder: (BuildContext context) => const _AddItemSheet(),
    );
  }
}

class _ItemRow extends GetView<ServiceFormController> {
  const _ItemRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final ServiceItemModel item = controller.items.value[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (item.partNumber.isNotEmpty)
                  Text(item.partNumber,
                      style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          SizedBox(
            width: 60,
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
                  text: item.qty.toStringAsFixed(0)),
              onChanged: (String value) => controller.updateItem(
                  index, qty: double.tryParse(value) ?? 1),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Rate',
                contentPadding:
                    EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              controller: TextEditingController(
                  text: item.unitPrice.toStringAsFixed(0)),
              onChanged: (String value) => controller.updateItem(
                  index, unitPrice: double.tryParse(value) ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(item.totalAmount.currency,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: const Color(0xFFDC2626),
            onPressed: () => controller.removeItem(index),
          ),
        ],
      ),
    );
  }
}

class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet();

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final ServiceFormController controller = Get.find<ServiceFormController>();

  String _type = 'part';
  final TextEditingController _name = TextEditingController();
  final TextEditingController _partNumber = TextEditingController();
  final TextEditingController _qty = TextEditingController(text: '1');
  final TextEditingController _price = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Add item',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment(value: 'part', label: Text('Part')),
                ButtonSegment(value: 'labour', label: Text('Labour')),
                ButtonSegment(value: 'other', label: Text('Other')),
              ],
              selected: <String>{_type},
              onSelectionChanged: (Set<String> s) =>
                  setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'Name *'),
            ),
            if (_type == 'part')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _partNumber,
                  decoration: const InputDecoration(labelText: 'Part number'),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Unit price (₹)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Add',
                size: AppButtonSize.small,
                onPressed: () {
                  controller.addItem(
                    itemType: _type,
                    name: _name.text.trim(),
                    partNumber: _partNumber.text.trim(),
                    qty: double.tryParse(_qty.text) ?? 1,
                    unitPrice: double.tryParse(_price.text) ?? 0,
                  );
                  Get.back();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
