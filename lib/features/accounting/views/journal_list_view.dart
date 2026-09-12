import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/accounting/controllers/accounting_controller.dart';
import 'package:enterprise_bike_showroom/features/accounting/models/accounting_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// General journal.
class JournalListView extends GetView<JournalController> {
  const JournalListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Journal',
      actions: <Widget>[
        const AppPermissionView(
          permission: Permissions.accountingCreate,
          child: AppButton(
            label: 'Manual Entry',
            icon: Icons.add,
            onPressed: _manual,
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
                      hint: 'Entry no. or narration…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Source',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'sales', label: 'Sales'),
                        DropdownOption<String?>(value: 'purchases', label: 'Purchases'),
                        DropdownOption<String?>(value: 'expenses', label: 'Expenses'),
                        DropdownOption<String?>(value: 'payments', label: 'Payments'),
                        DropdownOption<String?>(value: 'finance', label: 'Finance'),
                        DropdownOption<String?>(value: 'manual', label: 'Manual'),
                      ],
                      value: controller.state.filters['source_module'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('source_module', value),
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
                  child: AppTable<JournalEntryModel>(
                    items: controller.items.value,
                    keyOf: (JournalEntryModel j) => j.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: (JournalEntryModel j) => Get.toNamed(
                        AppRoutes.withId(AppRoutes.accountingTransactionDetails,
                            j.id!)),
                    emptyTitle: 'No journal entries',
                    emptyMessage: 'Entries are posted by business operations.',
                    columns: <AppColumn<JournalEntryModel>>[
                      AppColumn(
                        label: 'Entry #',
                        value: (JournalEntryModel j) =>
                            TableCells.text(j.entryNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Date',
                        value: (JournalEntryModel j) =>
                            TableCells.text(AppFormatters.date(j.entryDate)),
                      ),
                      AppColumn(
                        label: 'Source',
                        value: (JournalEntryModel j) => TableCells.text(
                            AppFormatters.humanize(j.sourceModule ?? '-')),
                      ),
                      AppColumn(
                        label: 'Narration',
                        value: (JournalEntryModel j) =>
                            TableCells.text(j.narration),
                      ),
                      AppColumn(
                        label: 'Debit = Credit',
                        numeric: true,
                        value: (JournalEntryModel j) =>
                            TableCells.text(j.totalDebit.currency),
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

  void _manual() => Get.toNamed(AppRoutes.accountingManualEntry)
      .then((_) => controller.refresh());
}
