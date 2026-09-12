import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/features/reports/controllers/report_controller.dart';
import 'package:enterprise_bike_showroom/features/reports/models/report_definition.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Report catalog.
class ReportCatalogView extends GetView<ReportCatalogController> {
  const ReportCatalogView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Reports',
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 110,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: controller.reports.length,
        itemBuilder: (BuildContext context, int index) {
          final ReportDefinition report = controller.reports[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Get.toNamed(AppRoutes.report,
                  parameters: <String, String>{'key': report.key}),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(report.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(report.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF64748B))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
