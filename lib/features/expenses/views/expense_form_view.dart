import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_date_picker.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/expenses/controllers/expense_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/image_service.dart';

/// New expense.
class ExpenseFormView extends GetView<ExpenseFormController> {
  const ExpenseFormView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.init());

    return AppShell(
      title: 'New Expense',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Save Expense',
            icon: Icons.save_outlined,
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
              if (controller.error.value.isNotEmpty) _banner(),
              AppCard(
                title: 'Expense',
                child: Column(
                  children: <Widget>[
                    AppDropdown<String?>(
                      label: 'Category',
                      options: <DropdownOption<String>>[
                        for (final c in controller.categories.value)
                          DropdownOption<String>(value: c.id, label: c.name),
                      ],
                      value: controller.categoryId.value,
                      onChanged: (String? value) =>
                          controller.categoryId.value = value,
                    ),
                    const SizedBox(height: 12),
                    AppDatePicker(
                      label: 'Date',
                      value: controller.date.value,
                      lastDate: DateTime.now(),
                      onChanged: (DateTime? value) =>
                          controller.date.value = value,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Description *',
                      maxLines: 2,
                      onChanged: (String value) =>
                          controller.description.value = value,
                    ),
                    AppTextField(
                      label: 'Amount *',
                      keyboardType: TextInputType.number,
                      onChanged: (String value) =>
                          controller.amount.value = double.tryParse(value) ?? 0,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppDropdown<String>(
                            label: 'Payment mode',
                            options: const <DropdownOption<String>>[
                              DropdownOption(value: 'cash', label: 'Cash'),
                              DropdownOption(value: 'upi', label: 'UPI'),
                              DropdownOption(value: 'card', label: 'Card'),
                              DropdownOption(value: 'cheque', label: 'Cheque'),
                              DropdownOption(value: 'bank_transfer', label: 'Bank Transfer'),
                            ],
                            value: controller.paymentMode.value,
                            onChanged: (String? value) =>
                                controller.paymentMode.value = value ?? 'cash',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Reference #',
                            onChanged: (String value) =>
                                controller.reference.value = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppTextField(
                            label: 'Voucher #',
                            onChanged: (String value) =>
                                controller.voucher.value = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Notes',
                            onChanged: (String value) =>
                                controller.notes.value = value,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Attachment (voucher / receipt photo)',
                actions: <Widget>[
                  Obx(() => AppButton(
                        label: controller.attachmentPath.value != null
                            ? 'Replace'
                            : 'Pick Image',
                        icon: Icons.photo_camera_outlined,
                        variant: AppButtonVariant.outlined,
                        onPressed: _pickAttachment,
                      )),
                ],
                child: Obx(() {
                  final String? path = controller.attachmentPath.value;
                  if (path == null || path.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('No attachment yet.',
                          style:
                              TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.file(File(path),
                        height: 140,
                        fit: BoxFit.cover,
                        gaplessPlayback: true),
                  );
                }),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      }),
    );
  }

  Widget _banner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(controller.error.value,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAttachment() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (file == null) return;
      final ImageService imageService = Get.find<ImageService>();
      final String path = await imageService.uploadDocument(
        bucket: StorageBuckets.expenseAttachments,
        collection: 'expenses',
        entityId: 'drafts',
        file: File(file.path),
      );
      controller.attachmentPath.value = path;
    } catch (e) {
      AppSnackbar.error(Get.context!, 'Could not upload attachment');
    }
  }

  Future<void> _submit(BuildContext context) async {
    final bool ok = await controller.submit();
    if (ok) {
      AppSnackbar.success(context, 'Expense saved');
      Get.until((route) => route.settings.name == AppRoutes.expenses);
    }
  }
}
