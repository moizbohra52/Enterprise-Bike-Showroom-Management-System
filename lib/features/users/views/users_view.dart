import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/common/models/user_model.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_filter_bar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/users/controllers/users_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Users & roles administration grid.
class UsersView extends GetView<UsersController> {
  const UsersView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Users',
      actions: <Widget>[
        AppPermissionView(
          permission: Permissions.usersCreate,
          child: AppButton(
            label: 'New user',
            icon: Icons.person_add_alt,
            onPressed: () => controller.openForm(),
          ),
        ),
      ],
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: AppFilterBar(
              children: <Widget>[
                // `AppFilterBar` is a Wrap, so children need intrinsic width.
                SizedBox(
                  width: 280,
                  child: AppSearchField(
                    hint: 'Search name, email or phone…',
                    onSearch: controller.updateSearch,
                  ),
                ),
                Obx(
                  () => AppFilterDropdown<String>(
                    label: 'Status',
                    value: controller.statusFilter.value.isEmpty
                        ? null
                        : controller.statusFilter.value,
                    options: const <DropdownOption<String>>[
                      DropdownOption(value: 'active', label: 'Active'),
                      DropdownOption(value: 'inactive', label: 'Inactive'),
                    ],
                    onChanged: controller.setStatusFilter,
                  ),
                ),
                Obx(
                  () => AppFilterDropdown<String>(
                    label: 'Showroom',
                    value: controller.showroomFilter.value.isEmpty
                        ? null
                        : controller.showroomFilter.value,
                    options: <DropdownOption<String>>[
                      for (final ShowroomModel showroom
                          in controller.session.accessibleShowrooms)
                        DropdownOption<String>(
                          value: showroom.id ?? '',
                          label: showroom.name,
                        ),
                    ],
                    onChanged: controller.setShowroomFilter,
                  ),
                ),
                TextButton.icon(
                  onPressed: controller.clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(
              () => AppTable<UserModel>(
                columns: _columns,
                items: controller.items.value,
                keyOf: (UserModel user) => user.id ?? '',
                info: controller.pageInfo.value,
                isLoading: controller.isLoading.value,
                error: controller.errorMessage.value.isEmpty
                    ? null
                    : controller.errorMessage.value,
                onRefresh: controller.refresh,
                onRowTap: controller.canEdit ? controller.openDetails : null,
                onPageChanged: controller.goToPage,
                onPageSizeChanged: controller.setPageSize,
                sortColumn: controller.sortField.value,
                sortAscending: controller.sortAscending.value,
                onSort: controller.setSort,
                emptyTitle: 'No users yet',
                emptyMessage: 'Create the first user to grant showroom access.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<AppColumn<UserModel>> get _columns => <AppColumn<UserModel>>[
        AppColumn<UserModel>(
          label: 'Name',
          expand: true,
          value: (UserModel user) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TableCells.text(user.name.isEmpty ? '-' : user.name, bold: true),
              TableCells.sub(user.email),
            ],
          ),
        ),
        AppColumn<UserModel>(
          label: 'Phone',
          value: (UserModel user) =>
              TableCells.text(AppFormatters.phone(user.phone)),
        ),
        AppColumn<UserModel>(
          label: 'Roles',
          value: (UserModel user) => TableCells.text(
            user.roleLabels.isEmpty ? 'Unassigned' : user.roleLabels.join(', '),
          ),
        ),
        AppColumn<UserModel>(
          label: 'Status',
          value: (UserModel user) => AppStatusChip(status: user.status),
        ),
        AppColumn<UserModel>(
          label: 'Last login',
          value: (UserModel user) => TableCells.text(
            user.lastLoginAt == null
                ? 'Never'
                : AppFormatters.dateTime(user.lastLoginAt),
          ),
        ),
      ];
}
