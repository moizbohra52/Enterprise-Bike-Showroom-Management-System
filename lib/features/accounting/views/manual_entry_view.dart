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
import 'package:enterprise_bike_showroom/features/accounting/controllers/accounting_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Manual journal entry (must balance: DR = CR).
class ManualEntryView extends GetView<ManualEntryController> {
  const ManualEntryView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.init());

    return AppShell(
      title: 'Manual Journal Entry',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Post Entry',
            icon: Icons.check_circle_outline,
            isLoading: controller.saving.value,
            onPressed: () => _submit(context),
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
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline,
                          color: Color(0xFFDC2626)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(controller.error.value,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              AppCard(
                title: 'Entry',
                child: Column(
                  children: <Widget>[
                    AppDatePicker(
                      label: 'Entry date',
                      value: controller.entryDate.value,
                      lastDate: DateTime.now(),
                      onChanged: (DateTime? value) =>
                          controller.entryDate.value = value,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Narration *',
                      onChanged: (String value) =>
                          controller.narration.value = value,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Lines',
                actions: <Widget>[
                  AppButton(
                    label: 'Add Line',
                    icon: Icons.add,
                    variant: AppButtonVariant.outlined,
                    onPressed: controller.addLine,
                  ),
                ],
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < controller.lines.value.length; i++)
                      _LineRow(index: i),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Balance',
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _total(context, 'Total Debit', controller.totalDebit),
                    ),
                    Expanded(
                      child: _total(context, 'Total Credit', controller.totalCredit),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: controller.balanced
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        controller.balanced ? 'Balanced ✓' : 'Not balanced',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: controller.balanced
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      }),
    );
  }

  Widget _total(BuildContext context, String label, num value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value.currency,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    final bool ok = await controller.submit();
    if (ok) {
      AppSnackbar.success(context, 'Entry posted');
      Get.until((route) => route.settings.name == AppRoutes.accountingTransactions);
    }
  }
}

class _LineRow extends GetView<ManualEntryController> {
  const _LineRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final line = controller.lines.value[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: AppDropdown<String?>(
                  label: 'Account',
                  options: <DropdownOption<String>>[
                    for (final a in controller.accounts.value)
                      DropdownOption<String>(
                          value: a.id, label: '${a.code} — ${a.name}'),
                  ],
                  value: line.accountId.isEmpty ? null : line.accountId,
                  onChanged: (String? value) =>
                      controller.updateLine(index, accountId: value),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment(value: 'debit', label: Text('DR')),
                  ButtonSegment(value: 'credit', label: Text('CR')),
                ],
                selected: <String>{line.side},
                onSelectionChanged: (Set<String> selection) =>
                    controller.updateLine(
                        index, side: selection.first),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Amount',
                  keyboardType: TextInputType.number,
                  initialValue:
                      line.amount > 0 ? line.amount.toStringAsFixed(0) : '',
                  onChanged: (String value) => controller.updateLine(
                      index, amount: double.tryParse(value) ?? 0),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: const Color(0xFFDC2626),
                onPressed: () => controller.removeLine(index),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
