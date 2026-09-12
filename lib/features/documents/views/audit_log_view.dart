import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/documents/controllers/attachment_controller.dart';
import 'package:enterprise_bike_showroom/features/documents/models/attachment_models.dart';

/// Audit log (immutable trail of every change).
class AuditLogView extends GetView<AuditController> {
  const AuditLogView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Audit Log',
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
                      hint: 'User, entity or action…',
                      onSearch: controller.updateSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Action',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'create', label: 'Create'),
                        DropdownOption<String?>(value: 'update', label: 'Update'),
                        DropdownOption<String?>(value: 'delete', label: 'Delete'),
                        DropdownOption<String?>(value: 'login', label: 'Login'),
                        DropdownOption<String?>(value: 'logout', label: 'Logout'),
                        DropdownOption<String?>(value: 'export', label: 'Export'),
                      ],
                      value: controller.state.filters['action'] as String?,
                      onChanged: (String? value) =>
                          controller.setFilter('action', value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Entity',
                      options: const <DropdownOption<String?>>[
                        DropdownOption<String?>(value: null, label: 'All'),
                        DropdownOption<String?>(value: 'sale', label: 'Sale'),
                        DropdownOption<String?>(value: 'invoice', label: 'Invoice'),
                        DropdownOption<String?>(value: 'payment', label: 'Payment'),
                        DropdownOption<String?>(value: 'customer', label: 'Customer'),
                        DropdownOption<String?>(value: 'inventory', label: 'Inventory'),
                        DropdownOption<String?>(value: 'expense', label: 'Expense'),
                        DropdownOption<String?>(value: 'user', label: 'User'),
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
                  child: AppTable<AuditLogModel>(
                    items: controller.items.value,
                    keyOf: (AuditLogModel a) => a.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    onRowTap: _details,
                    emptyTitle: 'No audit entries',
                    emptyMessage:
                        'Every create/update/delete is recorded here.',
                    columns: <AppColumn<AuditLogModel>>[
                      AppColumn(
                        label: 'When',
                        value: (AuditLogModel a) => TableCells.text(
                            AppFormatters.dateTime(a.createdAt)),
                      ),
                      AppColumn(
                        label: 'User',
                        value: (AuditLogModel a) =>
                            TableCells.text(a.userName, bold: true),
                      ),
                      AppColumn(
                        label: 'Action',
                        value: (AuditLogModel a) =>
                            AppStatusChip(status: a.action),
                      ),
                      AppColumn(
                        label: 'Entity',
                        value: (AuditLogModel a) => TableCells.text(
                            '${AppFormatters.humanize(a.entityType)} '
                            '${a.entityId.isEmpty ? '' : '· ${a.entityId.substring(0, a.entityId.length > 8 ? 8 : a.entityId.length)}…'}'),
                      ),
                      AppColumn(
                        label: 'Changes',
                        numeric: true,
                        value: (AuditLogModel a) =>
                            TableCells.text('${a.changes.length}'),
                      ),
                      AppColumn(
                        label: 'IP',
                        value: (AuditLogModel a) =>
                            TableCells.text(a.ipAddress.isEmpty ? '-' : a.ipAddress),
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

  Future<void> _details(AuditLogModel a) async {
    await showModalBottomSheet<void>(
      context: Get.context!,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => _AuditDetailSheet(entry: a),
    );
  }
}

class _AuditDetailSheet extends StatelessWidget {
  const _AuditDetailSheet({required this.entry});

  final AuditLogModel entry;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> changes = entry.changes;
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
              child: Text(
                '${entry.action.toUpperCase()} · '
                '${AppFormatters.humanize(entry.entityType)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _kv('When', AppFormatters.dateTime(entry.createdAt)),
                _kv('User', entry.userName),
                _kv('Entity ID', entry.entityId),
                _kv('IP', entry.ipAddress.isEmpty ? '-' : entry.ipAddress),
                _kv('Notes', entry.notes.isEmpty ? '-' : entry.notes),
                const SizedBox(height: 12),
                Text('Field changes',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (changes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No field-level changes captured.',
                        style:
                            TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                  ),
                for (final MapEntry<String, dynamic> e in changes.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(e.key,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${(e.value as Map)['from']}  →  ${(e.value as Map)['to']}',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
