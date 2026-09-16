import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_date_picker.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/controllers/inventory_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/models/inventory_models.dart';
import 'package:enterprise_bike_showroom/features/inventory/repositories/inventory_repository.dart';

/// Transfer bikes between showrooms (select available bikes).
class StockTransferView extends GetView<InventoryController> {
  // Not const: this widget owns mutable state (Rx / TextEditingController),
  // and a const constructor cannot have initialized instance fields.
  StockTransferView({super.key});

  @override
  Widget build(BuildContext context) {
    final RxBool saving = _saving;
    return AppShell(
      title: 'Stock Transfer',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Transfer',
            icon: Icons.swap_horiz,
            isLoading: saving.value,
            onPressed: saving.value ? null : () => _submit(context),
          ),
        ),
      ],
      child: _content(),
    );
  }

  final RxBool _saving = false.obs;
  final Set<String> _selected = <String>{};
  String? _targetShowroomId;
  DateTime? _transferDate;
  final TextEditingController _notes = TextEditingController();

  Widget _content() {
    final SessionController session = Get.find<SessionController>();
    return FutureBuilder<List<InventoryModel>>(
      future: controller.repository
          .list(PageQuery(
        pageSize: 100,
        filters: <String, dynamic>{
          'status': 'available',
          'showroom_id': session.activeShowroomId,
        },
      ))
          .then((dynamic r) => r.items as List<InventoryModel>),
      builder: (BuildContext context, AsyncSnapshot<List<InventoryModel>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoader();
        }
        final List<InventoryModel> available = snapshot.data ?? <InventoryModel>[];
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppCard(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Obx(
                        () => AppDropdown<String?>(
                          label: 'To Showroom *',
                          options: <DropdownOption<String?>>[
                            const DropdownOption<String?>(
                                value: null, label: 'Select showroom'),
                            for (final s in session.accessibleShowrooms)
                              if (s.id != session.activeShowroomId)
                                DropdownOption<String?>(
                                    value: s.id, label: s.name),
                          ],
                          value: _targetShowroomId,
                          onChanged: (String? value) =>
                              setState(() => _targetShowroomId = value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppDatePicker(
                        label: 'Transfer Date',
                        value: _transferDate,
                        onChanged: (DateTime? d) =>
                            setState(() => _transferDate = d),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: available.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No available bikes',
                      message:
                          'Only AVAILABLE bikes from the current showroom can be transferred.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: available.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final InventoryModel item = available[index];
                        final bool selected =
                            item.id != null && _selected.contains(item.id!);
                        return Card(
                          child: CheckboxListTile(
                            value: selected,
                            title: Text(item.productLabel),
                            subtitle: Text(
                              '${item.stockCode} · Chassis ${item.chassisNumber}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            secondary: const Icon(Icons.pedals_outlined),
                            onChanged: (bool value) => setState(() {
                              if (value) {
                                _selected.add(item.id!);
                              } else {
                                _selected.remove(item.id!);
                              }
                            }),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppCard(
                title: 'Transfers (recent)',
                child: FutureBuilder<List<StockTransferModel>>(
                  future: Get.find<InventoryRepository>().transfers(limit: 10),
                  builder: (BuildContext context,
                      AsyncSnapshot<List<StockTransferModel>> snapshot) {
                    final List<StockTransferModel> transfers =
                        snapshot.data ?? <StockTransferModel>[];
                    if (transfers.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No transfers yet.'),
                      );
                    }
                    return Column(
                      children: <Widget>[
                        for (final StockTransferModel t in transfers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: <Widget>[
                                AppStatusChip(status: t.status),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${t.inventoryIds.length} bike(s) · '
                                    '${AppFormatters.date(t.transferDate)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (_targetShowroomId == null) {
      AppSnackbar.error(context, 'Select the destination showroom.');
      return;
    }
    if (_selected.isEmpty) {
      AppSnackbar.error(context, 'Select at least one bike.');
      return;
    }
    final bool confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirm transfer'),
        content: Text(
          'Move ${_selected.length} bike(s) to the selected showroom?',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Transfer')),
        ],
      ),
    );
    if (confirmed != true) return;
    _saving.value = true;
    try {
      await Get.find<InventoryRepository>().transfer(
        inventoryIds: _selected.toList(),
        toShowroomId: _targetShowroomId!,
        transferDate: _transferDate,
        notes: _notes.text.trim(),
      );
      AppSnackbar.success(context, 'Transfer initiated');
      Get.back();
      controller.refresh();
    } on AppException catch (e) {
      AppSnackbar.error(context, e.message);
    } catch (e) {
      AppSnackbar.error(context, ErrorMapper.friendly(e));
    } finally {
      _saving.value = false;
    }
  }
}
