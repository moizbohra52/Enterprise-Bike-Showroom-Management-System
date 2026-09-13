import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dialog.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/documents/controllers/attachment_controller.dart';
import 'package:enterprise_bike_showroom/features/documents/models/attachment_models.dart';

/// Document register (all entity attachments).
class DocumentListView extends GetView<AttachmentController> {
  const DocumentListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Documents',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.documentsUpload,
          child: AppButton(
            label: 'Upload',
            icon: Icons.upload_file_outlined,
            onPressed: _upload,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            AppCard(
              padding: 12,
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: AppSearchField(
                      hint: 'File name, notes or entity…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Entity',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'customer', label: 'Customer'),
                        DropdownOption<String?>(value: 'vehicle', label: 'Vehicle'),
                        DropdownOption<String?>(value: 'invoice', label: 'Invoice'),
                        DropdownOption<String?>(value: 'service', label: 'Service'),
                        DropdownOption<String?>(value: 'expense', label: 'Expense'),
                        DropdownOption<String?>(value: 'purchase', label: 'Purchase'),
                      ],
                      value: controller.state.filters['entity_type'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('entity_type', value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(
                child: AppCard(
                  padding: 8,
                  child: AppTable<AttachmentModel>(
                    items: controller.items.value,
                    keyOf: (AttachmentModel a) => a.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    emptyTitle: 'No documents',
                    emptyMessage: 'Upload vouchers, KYC, receipts and more.',
                    columns: <AppColumn<AttachmentModel>>[
                      AppColumn(
                        label: 'File',
                        value: (AttachmentModel a) =>
                            TableCells.text(a.fileName, bold: true),
                      ),
                      AppColumn(
                        label: 'Entity',
                        value: (AttachmentModel a) =>
                            TableCells.text(AppFormatters.humanize(a.entityType)),
                      ),
                      AppColumn(
                        label: 'Type',
                        value: (AttachmentModel a) =>
                            TableCells.text(a.mimeType),
                      ),
                      AppColumn(
                        label: 'Size',
                        numeric: true,
                        value: (AttachmentModel a) =>
                            TableCells.text(a.sizeLabel),
                      ),
                      AppColumn(
                        label: 'Uploaded',
                        value: (AttachmentModel a) =>
                            TableCells.text(AppFormatters.dateTime(a.createdAt)),
                      ),
                      AppColumn(
                        label: '',
                        value: (AttachmentModel a) => IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: const Color(0xFFDC2626),
                          onPressed: () => _remove(a),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(AttachmentModel a) async {
    final bool ok = await AppDialog.confirm(
      context,
      title: 'Delete document',
      message: 'Delete ${a.fileName}? Financial records are never '
          'physically removed — the row is soft-deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    final bool done = await controller.remove(a);
    if (done) AppSnackbar.success(context, 'Document removed');
  }

  Future<void> _upload() async {
    await showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => const _UploadSheet(),
    );
  }
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet();

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final AttachmentController controller = Get.find<AttachmentController>();

  String _entityType = 'customer';
  final TextEditingController _entityId = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  String? _pickedPath;
  bool _busy = false;

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
            Text('Upload document',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            AppDropdown<String>(
              label: 'Entity type',
              options: const <DropdownOption<String>>[
                DropdownOption(value: 'customer', label: 'Customer'),
                DropdownOption(value: 'vehicle', label: 'Vehicle'),
                DropdownOption(value: 'invoice', label: 'Invoice'),
                DropdownOption(value: 'service', label: 'Service'),
                DropdownOption(value: 'expense', label: 'Expense'),
                DropdownOption(value: 'purchase', label: 'Purchase'),
              ],
              value: _entityType,
              onChanged: (String? value) =>
                  setState(() => _entityType = value ?? 'customer'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _entityId,
              decoration:
                  const InputDecoration(labelText: 'Entity ID (uuid)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: _pickedPath == null ? 'Pick file' : 'Replace file',
              icon: Icons.attach_file_outlined,
              variant: AppButtonVariant.outlined,
              onPressed: _busy ? null : _pick,
            ),
            if (_pickedPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_pickedPath!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B))),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Upload',
                size: AppButtonSize.small,
                isLoading: _busy,
                onPressed: _busy ? null : _upload,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    setState(() => _pickedPath = file.path);
  }

  Future<void> _upload() async {
    final String? path = _pickedPath;
    if (path == null || _entityId.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Pick a file and enter the entity ID.');
      return;
    }
    setState(() => _busy = true);
    try {
      final File file = File(path);
      final String storagePath = await controller.imageService.uploadDocument(
        bucket: SupabaseConfig.StorageBuckets.customerDocuments,
        collection: _entityType,
        entityId: _entityId.text.trim(),
        file: file,
      );
      final bool ok = await controller.upload(
        storagePath: storagePath,
        fileName: path.split('/').last,
        mimeType: 'image/jpeg',
        fileSize: file.lengthSync(),
        entityType: _entityType,
        entityId: _entityId.text.trim(),
        notes: _notes.text.trim(),
      );
      if (ok) {
        AppSnackbar.success(context, 'Document uploaded');
        Get.back();
      }
    } catch (e) {
      AppSnackbar.error(context, 'Upload failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
