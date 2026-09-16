import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/features/inventory/controllers/inventory_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/models/inventory_models.dart';
import 'package:enterprise_bike_showroom/features/inventory/repositories/inventory_repository.dart';

/// Stock adjustment: pick a bike, change status / location with a reason.
class StockAdjustView extends GetView<InventoryController> {
  // Not const: this widget owns mutable state (Rx / TextEditingController),
  // and a const constructor cannot have initialized instance fields.
  StockAdjustView({super.key});

  @override
  Widget build(BuildContext context) {
    final RxBool saving = _saving;
    return AppShell(
      title: 'Stock Adjustment',
      showBack: true,
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: 'Apply Adjustment',
            icon: Icons.check,
            isLoading: saving.value,
            onPressed: saving.value ? null : () => _submit(context),
          ),
        ),
      ],
      child: _content(),
    );
  }

  final RxBool _saving = false.obs;
  final Rx<String> _search = ''.obs;
  final Rx<InventoryModel?> _selected = Rx<InventoryModel?>(null);
  final RxnString _newStatus = RxnString();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  Widget _content() {
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                AppCard(
                  padding: 12,
                  child: AppSearchField(
                    hint: 'Find bike by chassis / engine…',
                    onSearch: (String q) => _search.value = q,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Obx(() => FutureBuilder<List<InventoryModel>>(
                        future: controller.repository.list(PageQuery(
                          pageSize: 100,
                          search: _search.value.isEmpty
                              ? null
                              : _search.value,
                        )),
                        builder: (BuildContext context,
                            AsyncSnapshot<List<InventoryModel>> snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const AppLoader();
                          }
                          final List<InventoryModel> bikes =
                              snapshot.data ?? <InventoryModel>[];
                          if (bikes.isEmpty) {
                            return const AppEmptyState(
                              icon: Icons.inventory_2_outlined,
                              title: 'No bikes found',
                            );
                          }
                          return ListView.separated(
                            itemCount: bikes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (BuildContext context, int index) {
                              final InventoryModel bike = bikes[index];
                              final bool selected = _selected.value?.id ==
                                  bike.id;
                              return Card(
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha(24)
                                    : null,
                                child: ListTile(
                                  title: Text(bike.productLabel),
                                  subtitle: Text(
                                      '${bike.stockCode} · ${bike.chassisNumber}'),
                                  leading: Radio<InventoryModel>(
                                    value: bike,
                                    groupValue: _selected.value,
                                    onChanged: (InventoryModel? value) =>
                                        _selected.value = value,
                                  ),
                                  isThreeLine: false,
                                ),
                              );
                            },
                          );
                        },
                      )),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Obx(() {
              final InventoryModel? bike = _selected.value;
              if (bike == null) {
                return const AppEmptyState(
                  icon: Icons.touch_app_outlined,
                  title: 'Select a bike',
                  message: 'Pick a bike from the list to adjust it.',
                );
              }
              return AppCard(
                title: 'Adjust ${bike.stockCode}',
                subtitle: bike.productLabel,
                child: Column(
                  children: <Widget>[
                    Obx(() => AppDropdown<String?>(
                      label: 'New Status *',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'Select'),
                        DropdownOption<String?>(value: 'available', label: 'Available'),
                        DropdownOption<String?>(value: 'reserved', label: 'Reserved'),
                        DropdownOption<String?>(value: 'demo', label: 'Demo'),
                        DropdownOption<String?>(value: 'damaged', label: 'Damaged'),
                        DropdownOption<String?>(value: 'in_transit', label: 'In Transit'),
                        DropdownOption<String?>(value: 'returned', label: 'Returned'),
                      ],
                      value: _newStatus.value,
                      onChanged: (String? value) =>
                          _newStatus.value = value,
                    )),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'New Location',
                      controller: _location,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Reason *',
                      maxLines: 3,
                      controller: _reason,
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    final InventoryModel? bike = _selected.value;
    if (bike == null || bike.id == null) {
      AppSnackbar.error(context, 'Select a bike to adjust.');
      return;
    }
    if (_newStatus.value == null) {
      AppSnackbar.error(context, 'Select the new status.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      AppSnackbar.error(context, 'A reason is required for adjustments.');
      return;
    }
    _saving.value = true;
    try {
      await Get.find<InventoryRepository>().adjust(
        inventoryId: bike.id!,
        newStatus: _newStatus.value!,
        location: _location.text.trim().isEmpty
            ? null
            : _location.text.trim(),
        reason: _reason.text.trim(),
      );
      AppSnackbar.success(context, 'Stock adjusted');
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
