import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dropdown.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_table.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/freeservice/controllers/free_service_controller.dart';
import 'package:enterprise_bike_showroom/features/freeservice/models/free_service_models.dart';

/// Free-service dashboard: grants + plans.
class FreeServiceView extends GetView<FreeServiceController> {
  const FreeServiceView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Free Service',
      child: Obx(() {
        final List<FreeServiceGrantModel> grants = controller.items.value;
        final int active =
            grants.where((FreeServiceGrantModel g) => g.status == 'active').length;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppStatCard(
                        title: 'Total grants (page)',
                        value: '${grants.length}',
                        icon: Icons.card_giftcard),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppStatCard(
                        title: 'Available',
                        value: '$active',
                        icon: Icons.verified_user,
                        color: const Color(0xFF16A34A)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppStatCard(
                        title: 'Plans',
                        value: '${controller.plans.value.length}',
                        icon: Icons.menu_book_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: 12,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: AppSearchField(
                        hint: 'Grant no. or registration…',
                        onSearch: controller.updateSearch,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppDropdown<String?>(
                        label: 'Status',
                        options: const <DropdownOption<String?>>[
                          DropdownOption<String?>(value: null, label: 'All'),
                          DropdownOption<String?>(value: 'active', label: 'Active'),
                          DropdownOption<String?>(value: 'used', label: 'Used'),
                          DropdownOption<String?>(value: 'expired', label: 'Expired'),
                        ],
                        value: controller.state.filters['status'] as String?,
                        onChanged: (String? value) =>
                            controller.setFilter('status', value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AppCard(
                  padding: 8,
                  child: AppTable<FreeServiceGrantModel>(
                    items: grants,
                    keyOf: (FreeServiceGrantModel g) => g.id ?? '',
                    info: controller.pageInfo.value,
                    isLoading: controller.isLoading.value,
                    error: controller.errorMessage.value.isEmpty
                        ? null
                        : controller.errorMessage.value,
                    onRefresh: controller.refresh,
                    onPageChanged: controller.goToPage,
                    onPageSizeChanged: controller.setPageSize,
                    emptyTitle: 'No free-service grants',
                    emptyMessage:
                        'Grants are issued automatically with warranty sales.',
                    columns: <AppColumn<FreeServiceGrantModel>>[
                      AppColumn(
                        label: 'Grant #',
                        value: (FreeServiceGrantModel g) =>
                            TableCells.text(g.grantNumber, bold: true),
                      ),
                      AppColumn(
                        label: 'Vehicle',
                        value: (FreeServiceGrantModel g) =>
                            TableCells.text(g.vehicleLabel),
                      ),
                      AppColumn(
                        label: 'Plan',
                        value: (FreeServiceGrantModel g) =>
                            TableCells.text(g.planName),
                      ),
                      AppColumn(
                        label: 'Valid till',
                        value: (FreeServiceGrantModel g) =>
                            TableCells.text(AppFormatters.date(g.endDate)),
                      ),
                      AppColumn(
                        label: 'Mileage left',
                        numeric: true,
                        value: (FreeServiceGrantModel g) => TableCells.text(
                            '${AppFormatters.km(g.remainingMileage)}'),
                      ),
                      AppColumn(
                        label: 'Status',
                        value: (FreeServiceGrantModel g) =>
                            AppStatusChip(status: g.status),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Obx(() => _plansCard()),
            ],
          ),
        );
      }),
    );
  }

  Widget _plansCard() {
    final List<FreeServicePlanModel> plans = controller.plans.value;
    return AppCard(
      title: 'Free-service plans',
      child: plans.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: Text('No active plans.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            )
          : Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                for (final FreeServicePlanModel plan in plans)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(plan.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          '${plan.productName.isEmpty ? '' : plan.productName + ' · '} '
                          '${AppFormatters.km(plan.serviceKm)} / '
                          '${plan.serviceDays} days',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
