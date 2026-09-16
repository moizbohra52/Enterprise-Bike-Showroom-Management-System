import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/features/reports/controllers/report_controller.dart';
import 'package:enterprise_bike_showroom/features/reports/models/report_definition.dart';
import 'package:enterprise_bike_showroom/services/export_service.dart';

/// A single report: columns + rows + CSV / Excel / PDF export.
class ReportView extends GetView<ReportViewController> {
  const ReportView({super.key});

  @override
  Widget build(BuildContext context) {
    final String key = Get.parameters['key'] ?? '';
    if (key.isEmpty) {
      return AppShell(
          title: 'Report',
          showBack: true,
          child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.load(key));

    return AppShell(
      title: 'Report',
      showBack: true,
      actions: <Widget>[
        Obx(() => AppButton(
              label: 'CSV',
              icon: Icons.grid_on,
              variant: AppButtonVariant.outlined,
              isLoading: controller.exporting.value,
              onPressed: () => _export(context, 'csv'),
            )),
        const SizedBox(width: 8),
        Obx(() => AppButton(
              label: 'Excel',
              icon: Icons.table_chart_outlined,
              variant: AppButtonVariant.outlined,
              isLoading: controller.exporting.value,
              onPressed: () => _export(context, 'excel'),
            )),
        const SizedBox(width: 8),
        Obx(() => AppButton(
              label: 'PDF',
              icon: Icons.picture_as_pdf,
              variant: AppButtonVariant.outlined,
              isLoading: controller.exporting.value,
              onPressed: () => _export(context, 'pdf'),
            )),
        const SizedBox(width: 8),
        Obx(() => AppButton(
              label: 'Refresh',
              icon: Icons.refresh,
              variant: AppButtonVariant.outlined,
              onPressed: controller.isLoading
                  ? null
                  : controller.refresh,
            )),
      ],
      child: Obx(() {
        final ReportDefinition? d = controller.definition.value;
        if (d == null) {
          return const AppLoader();
        }
        final List<Map<String, dynamic>> rows = controller.rows.value;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(d.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(d.description,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B))),
              const SizedBox(height: 12),
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
              Expanded(
                child: AppCard(
                  padding: 8,
                  child: controller.isLoading.value && rows.isEmpty
                      ? const AppLoader()
                      : AppTable<List<String>>(
                          items: <List<String>>[
                            for (final Map<String, dynamic> row in rows)
                              d.rowToDisplay(row),
                          ],
                          keyOf: (List<String> row) =>
                              row.join('|').hashCode.toString(),
                          info: const PageInfo(
                              page: 1, pageSize: 1000, total: 1000),
                          emptyTitle: 'No data',
                          columns: <AppColumn<List<String>>>[
                            for (int i = 0; i < d.columns.length; i++)
                              AppColumn(
                                label: d.columns[i],
                                numeric: _isNumericColumn(d, i),
                                value: (List<String> row) => TableCells.text(
                                    i < row.length ? row[i] : '-'),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  bool _isNumericColumn(ReportDefinition d, int i) {
    final String c = d.columns[i].toLowerCase();
    return c.contains('amount') ||
        c.contains('count') ||
        c.contains('total') ||
        c.contains('profit') ||
        c.contains('revenue') ||
        c.contains('cost') ||
        c.contains('value') ||
        c.contains('quantity') ||
        c.contains('emi') ||
        c.contains('days');
  }

  Future<void> _export(BuildContext context, String format) async {
    final ReportDefinition? d = controller.definition.value;
    if (d == null) return;
    final ExportService export = Get.find<ExportService>();
    controller.exporting.value = true;
    try {
      final List<List<dynamic>> rows = <List<dynamic>>[
        for (final Map<String, dynamic> row in controller.rows.value)
          d.rowToDisplay(row),
      ];
      final String safeName =
          d.key.replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final String path;
      switch (format) {
        case 'excel':
          path = await export.saveExcel(
            fileName: '$safeName.xlsx',
            sheetName: d.title,
            columns: d.columns,
            rows: rows,
          );
          break;
        case 'pdf':
          path = await export.savePdfReport(
            fileName: '$safeName.pdf',
            title: d.title,
            columns: d.columns,
            rows: rows,
          );
          break;
        default:
          path = await export.saveCsv(
            fileName: '$safeName.csv',
            columns: d.columns,
            rows: rows,
          );
          break;
      }
      AppSnackbar.success(context, 'Saved to $path');
      await export.openFile(path);
    } catch (e) {
      AppSnackbar.error(context, 'Export failed');
    } finally {
      controller.exporting.value = false;
    }
  }
}
