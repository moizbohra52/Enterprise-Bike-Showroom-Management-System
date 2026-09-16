import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/features/showroom/controllers/showroom_controller.dart';

/// Showroom list (desktop grid / mobile cards).
class ShowroomListView extends GetView<ShowroomController> {
  const ShowroomListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Showrooms',
      actions: <Widget>[
        AppPermissionView(
          permission: Permissions.showroomCreate,
          child: AppButton(
            label: 'Add Showroom',
            icon: Icons.add,
            onPressed: _add,
          ),
        ),
      ],
      child: _content(),
    );
  }

  void _add() => controller.openForm();

  Widget _content() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Obx(() {
        return Column(
          children: <Widget>[
            AppCard(
              padding: 12,
              child: AppSearchField(
                hint: 'Search by name, code or city…',
                onSearch: controller.updateSearch,
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: 8,
              child: AppTable<ShowroomModel>(
                items: controller.items.value,
                keyOf: (ShowroomModel s) => s.id ?? '',
                info: controller.pageInfo.value,
                isLoading: controller.isLoading.value,
                error: controller.errorMessage.value.isEmpty
                    ? null
                    : controller.errorMessage.value,
                onRefresh: controller.refresh,
                onPageChanged: controller.goToPage,
                onPageSizeChanged: controller.setPageSize,
                onRowTap: controller.openDetails,
                emptyTitle: 'No showrooms yet',
                emptyMessage: 'Create your first showroom to get started.',
                columns: <AppColumn<ShowroomModel>>[
                  AppColumn(
                    label: 'Code',
                    value: (ShowroomModel s) => TableCells.text(s.code, bold: true),
                  ),
                  AppColumn(
                    label: 'Name',
                    value: (ShowroomModel s) => TableCells.text(s.name),
                  ),
                  AppColumn(
                    label: 'City',
                    value: (ShowroomModel s) => TableCells.text(s.city),
                  ),
                  AppColumn(
                    label: 'Phone',
                    value: (ShowroomModel s) =>
                        TableCells.text(AppFormatters.phone(s.phone)),
                  ),
                  AppColumn(
                    label: 'GSTIN',
                    value: (ShowroomModel s) => TableCells.text(s.gstNumber),
                  ),
                  AppColumn(
                    label: 'Status',
                    value: (ShowroomModel s) =>
                        AppStatusChip(status: s.status),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
