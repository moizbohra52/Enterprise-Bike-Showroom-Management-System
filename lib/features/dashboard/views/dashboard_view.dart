import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_error_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_permission_view.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_responsive_layout.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/dashboard/controllers/dashboard_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Landing screen: KPIs for the active showroom, quick actions and the most
/// recent sales.
class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Dashboard',
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: controller.refresh,
        ),
      ],
      child: Obx(
        () {
          if (controller.isLoading.value &&
              controller.recentSales.isEmpty &&
              controller.customersTotal.value == 0) {
            return const AppLoader(message: 'Loading dashboard…');
          }
          if (controller.errorMessage.value.isNotEmpty &&
              controller.customersTotal.value == 0) {
            return AppErrorState(
              message: controller.errorMessage.value,
              onRetry: controller.refresh,
            );
          }
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _greeting(context, session),
                const SizedBox(height: AppSpacing.md),
                _kpis(),
                const SizedBox(height: AppSpacing.sm),
                _quickActions(),
                const SizedBox(height: AppSpacing.sm),
                _recentSales(context),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _greeting(BuildContext context, SessionController session) {
    final ThemeData theme = Theme.of(context);
    final String showroom = session.activeShowroom?.name ?? 'All showrooms';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Hello ${session.displayName}',
          style: theme.textTheme.titleLarge,
        ),
        Text(
          showroom,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _kpis() {
    final List<AppStatCard> cards = <AppStatCard>[
      AppStatCard(
        title: "Today's sales",
        value: AppFormatters.number(controller.salesToday.value),
        icon: Icons.point_of_sale_outlined,
        color: AppColors.primary,
        caption: AppFormatters.amount(controller.revenueToday.value),
      ),
      AppStatCard(
        title: 'Revenue this month',
        value: AppFormatters.compactMoney(controller.revenueMonth.value),
        icon: Icons.trending_up,
        color: AppColors.info,
      ),
      AppStatCard(
        title: 'Outstanding',
        value: AppFormatters.compactMoney(controller.outstanding.value),
        icon: Icons.pending_actions_outlined,
        color: AppColors.warning,
        caption: 'Unpaid invoices',
      ),
      AppStatCard(
        title: 'EMI due soon',
        value: AppFormatters.number(controller.emiDueSoon.value),
        icon: Icons.calendar_month_outlined,
        color: AppColors.danger,
        caption: 'Next 3 days',
      ),
      AppStatCard(
        title: 'Open service jobs',
        value: AppFormatters.number(controller.openServiceJobs.value),
        icon: Icons.build_outlined,
        color: AppColors.neutral,
      ),
      AppStatCard(
        title: 'Units in stock',
        value: AppFormatters.number(controller.stockUnits.value),
        icon: Icons.inventory_2_outlined,
        color: AppColors.primaryDark,
      ),
      AppStatCard(
        title: 'Customers',
        value: AppFormatters.number(controller.customersTotal.value),
        icon: Icons.people_alt_outlined,
        color: AppColors.success,
      ),
    ];

    return AppResponsiveLayout(
      mobile: (_) => Column(
        children: <Widget>[
          for (final AppStatCard card in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: card,
            ),
        ],
      ),
      tablet: (_) => _grid(cards, 2),
      desktop: (_) => _grid(cards, 4),
    );
  }

  Widget _grid(List<AppStatCard> cards, int columns) {
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.3,
      children: cards,
    );
  }

  Widget _quickActions() {
    return AppCard(
      title: 'Quick actions',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          AppPermissionView(
            permission: Permissions.salesCreate,
            child: AppButton(
              label: 'New sale',
              icon: Icons.add_shopping_cart,
              onPressed: () => Get.toNamed(AppRoutes.saleForm),
            ),
          ),
          AppPermissionView(
            permission: Permissions.customersCreate,
            child: AppButton(
              label: 'New customer',
              icon: Icons.person_add_alt,
              onPressed: () => Get.toNamed(AppRoutes.customerForm),
            ),
          ),
          AppPermissionView(
            permission: Permissions.serviceCreate,
            child: AppButton(
              label: 'Open job card',
              icon: Icons.handyman_outlined,
              onPressed: () => Get.toNamed(AppRoutes.serviceForm),
            ),
          ),
          AppPermissionView(
            permission: Permissions.paymentsCreate,
            child: AppButton(
              label: 'Record payment',
              icon: Icons.payments_outlined,
              onPressed: () => Get.toNamed(AppRoutes.paymentForm),
            ),
          ),
          AppPermissionView(
            permission: Permissions.inventoryView,
            child: AppButton(
              label: 'Stock in',
              icon: Icons.inventory_outlined,
              onPressed: () => Get.toNamed(AppRoutes.stockIn),
            ),
          ),
          AppPermissionView(
            permission: Permissions.reportsView,
            child: AppButton(
              label: 'Reports',
              icon: Icons.query_stats,
              onPressed: () => Get.toNamed(AppRoutes.reports),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentSales(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      title: 'Recent sales',
      actions: <Widget>[
        TextButton(
          onPressed: () => Get.toNamed(AppRoutes.sales),
          child: const Text('View all'),
        ),
      ],
      child: controller.recentSales.isEmpty
          ? const AppEmptyState(
              title: 'No sales recorded yet',
              message: 'Sold bikes will appear here with their payment state.',
            )
          : Column(
              children: <Widget>[
                for (final Map<String, dynamic> sale
                    in controller.recentSales)
                  _saleRow(theme, sale),
              ],
            ),
    );
  }

  Widget _saleRow(ThemeData theme, Map<String, dynamic> sale) {
    final Map<String, dynamic> customer = SafeJson.asMap(sale['customer']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  SafeJson.asText(sale['sale_number'], fallback: 'Sale'),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${SafeJson.asText(customer['name'], fallback: 'Walk-in')} · '
                  '${AppFormatters.date(sale['sale_date'])}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            AppFormatters.amount(SafeJson.asMoney(sale['total_amount'])),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(width: 12),
          AppStatusChip(status: SafeJson.asText(sale['status'])),
        ],
      ),
    );
  }
}
