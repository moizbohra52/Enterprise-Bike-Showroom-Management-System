import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/features/payments/controllers/payment_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Record a payment against an invoice.
class PaymentFormView extends GetView<PaymentFormController> {
  // Not const: this widget owns mutable state (Rx / TextEditingController),
  // and a const constructor cannot have initialized instance fields.
  PaymentFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? invoiceId = Get.parameters['invoiceId'];
    final String? saleId = Get.parameters['saleId'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.init(invoiceId: invoiceId, saleId: saleId);
    });

    return AppShell(
      title: 'New Payment',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Record Payment',
            icon: Icons.check_circle_outline,
            isLoading: controller.saving.value,
            onPressed: () => _submit(context),
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
              AppCard(
                title: 'Invoice',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppTextField(
                            label: 'Invoice ID (paste from sale/invoice screen)',
                            controller: _invoiceField,
                            onChanged: (String value) =>
                                controller.invoiceId.value = value.trim(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        AppButton(
                          label: 'Load',
                          icon: Icons.refresh,
                          variant: AppButtonVariant.outlined,
                          onPressed: () async {
                            final String id = _invoiceField.text.trim();
                            if (id.isNotEmpty) {
                              await controller.init(invoiceId: id);
                            }
                          },
                        ),
                      ],
                    ),
                    Obx(
                      () => controller.invoiceId.value.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: AppStatCard(
                                title: 'Outstanding on invoice',
                                value: controller.outstanding.value.currency,
                                icon: Icons.hourglass_bottom,
                                color: controller.outstanding.value > 0
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF16A34A),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Payment',
                child: Column(
                  children: <Widget>[
                    AppTextField(
                      label: 'Amount *',
                      keyboardType: TextInputType.number,
                      controller: _amountField,
                      onChanged: (String value) =>
                          controller.amount.value =
                              double.tryParse(value) ?? 0,
                    ),
                    AppDropdown<String>(
                      label: 'Payment mode',
                      options: const <DropdownOption<String>>[
                        DropdownOption(value: 'cash', label: 'Cash'),
                        DropdownOption(value: 'upi', label: 'UPI'),
                        DropdownOption(value: 'card', label: 'Card'),
                        DropdownOption(value: 'cheque', label: 'Cheque'),
                        DropdownOption(value: 'bank_transfer', label: 'Bank Transfer'),
                      ],
                      value: controller.mode.value,
                      onChanged: (String? value) =>
                          controller.mode.value = value ?? 'cash',
                    ),
                    AppTextField(
                      label: 'Reference number (cheque / UPI ref)',
                      controller: _referenceField,
                      onChanged: (String value) =>
                          controller.reference.value = value,
                    ),
                    AppTextField(
                      label: 'Notes',
                      maxLines: 2,
                      controller: _notesField,
                      onChanged: (String value) => controller.notes.value = value,
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

  final TextEditingController _invoiceField = TextEditingController();
  final TextEditingController _amountField = TextEditingController();
  final TextEditingController _referenceField = TextEditingController();
  final TextEditingController _notesField = TextEditingController();

  Future<void> _submit(BuildContext context) async {
    final bool ok = await controller.submit();
    if (ok) {
      AppSnackbar.success(context, 'Payment recorded');
      Get.until((route) => route.settings.name == AppRoutes.payments);
    }
  }
}
