import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/future_cache.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/accounting/controllers/accounting_controller.dart';
import 'package:enterprise_bike_showroom/features/accounting/models/accounting_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Chart of accounts.
class AccountListView extends GetView<AccountController> {
  const AccountListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Accounts',
      actions: <Widget>[
        AppPermissionView(
          permission: Permissions.accountingCreate,
          child: AppButton(
            label: 'New Account',
            icon: Icons.account_tree_outlined,
            onPressed: _newAccount,
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
                      hint: 'Code or name…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Type',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'asset', label: 'Asset'),
                        DropdownOption<String?>(value: 'liability', label: 'Liability'),
                        DropdownOption<String?>(value: 'equity', label: 'Equity'),
                        DropdownOption<String?>(value: 'income', label: 'Income'),
                        DropdownOption<String?>(value: 'expense', label: 'Expense'),
                      ],
                      value: controller.state.filters['type'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('type', value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(
                () => AppCard(
                  padding: 8,
                  child: AppTable<AccountModel>(
                    items: controller.items.value,
                    keyOf: (AccountModel a) => a.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: _ledger,
                    emptyTitle: 'No accounts',
                    emptyMessage: 'Default accounts are created per showroom.',
                    columns: <AppColumn<AccountModel>>[
                      AppColumn(
                        label: 'Code',
                        value: (AccountModel a) =>
                            TableCells.text(a.code, bold: true),
                      ),
                      AppColumn(
                        label: 'Name',
                        value: (AccountModel a) => TableCells.text(a.name),
                      ),
                      AppColumn(
                        label: 'Type',
                        value: (AccountModel a) =>
                            TableCells.text(AppFormatters.humanize(a.type)),
                      ),
                      AppColumn(
                        label: 'Sub-type',
                        value: (AccountModel a) => TableCells.text(
                            a.subType == null || a.subType!.isEmpty
                                ? '-'
                                : AppFormatters.humanize(a.subType!)),
                      ),
                      AppColumn(
                        label: 'System',
                        value: (AccountModel a) =>
                            TableCells.text(a.isSystem ? 'Yes' : 'No'),
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

  void _newAccount() =>
      Get.toNamed(AppRoutes.accountForm)?.then((_) => controller.refresh());

  Future<void> _ledger(AccountModel account) async {
    await showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => _LedgerSheet(account: account),
    );
  }
}

class _LedgerSheet extends GetView<AccountController> {
  const _LedgerSheet({required this.account});

  final AccountModel account;

  @override
  Widget build(BuildContext context) {
    return FutureCache<List<Map<String, dynamic>>>(
      future: () => controller.ledger(account),
      builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: AppLoader(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load ledger: ${snapshot.error}'),
          );
        }
        final List<Map<String, dynamic>> rows = snapshot.data ?? <Map<String, dynamic>>[];
        num balance = 0;
        return ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${account.code} — ${account.name}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('No movements yet.',
                            style:
                                TextStyle(color: Color(0xFF64748B))))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> row = rows[index];
                          final num debit =
                              (row['debit'] as num?)?.toDouble() ?? 0;
                          final num credit =
                              (row['credit'] as num?)?.toDouble() ?? 0;
                          balance += debit - credit;
                          return ListTile(
                            dense: true,
                            title: Text(
                                '${AppFormatters.date(row['entry_date'])} · ${row['entry_number'] ?? ''}',
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                row['narration']?.toString() ?? '',
                                style: const TextStyle(fontSize: 12)),
                            trailing: Text(
                              '${debit > 0 ? debit.currency : ''}  '
                              '${credit > 0 ? '-${credit.currency}' : ''}  '
                              '·  ${balance.currency}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
