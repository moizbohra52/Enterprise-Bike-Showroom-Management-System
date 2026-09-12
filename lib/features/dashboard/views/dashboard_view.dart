import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_chart.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_error_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/core/utils/date_utils.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/dashboard/controllers/dashboard_controller.dart';
import 'package:enterprise_bike_showroom/features/dashboard/repositories/dashboard_repository.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Role-aware landing page: KPIs, revenue trend, recent sales, follow-ups.
class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  SessionController get _session => Get.find<SessionController>();

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Dashboard',
      actions: <Widget>[
        Obx(
          () => AppButton(
            label: controller.isLoading.value ? 'Refreshing…' : 'Refresh',
            icon: Icons.refresh,
            variant: AppButtonVariant.outlined,
            size: AppButtonSize.small,
            isLoading: controller.isLoading.value,
            onPressed: controller.refresh,
          ),
        ),
      ],
      child: Obx(() {
        final DashboardSnapshot? data = controller.snapshot.value;
        if (data == null) {
          if (controller.error.value.isNotEmpty) {
            return AppErrorState(
              message: controller.error.value,
              onRetry: controller.refresh,
            );
          }
          return const AppLoader(message: 'Loading showroom summary…');
        }
        if (data.isBlank) {
          return _firstRun(context, data);
        }
        return _scroll(context, data);
      }),
    );
  }

  // ------------------------------------------------------------------ states

  Widget _firstRun(BuildContext context, DashboardSnapshot data) {
    return Center(
      child: AppEmptyState(
        icon: Icons.roofing_outlined,
        title: 'Nothing to summarise yet',
        message: 'Showroom activity (sales, payments, job cards) appears here '
            'as soon as it is recorded - last checked '
            '${DateUtils.formatDateTime(data.generatedAt)}.',
        actionLabel: _session.can(Permissions.salesCreate) ? 'New sale' : null,
        onAction: _session.can(Permissions.salesCreate)
            ? () => Get.toNamed(AppRoutes.saleForm)
            : null,
      ),
    );
  }

  // -------------------------------------------------------------------- body

  Widget _scroll(BuildContext context, DashboardSnapshot d) {
    final int columns = context.isDesktop ? 4 : (context.isTablet ? 2 : 1);
    final List<Widget> stats = <Widget>[
      _saleMetrics(d),
      _collectionMetric(d),
      _receivableMetric(d),
      _emiMetric(d),
      _jobMetric(d),
      _expenseMetric(d),
      _stockMetric(d),
      _customerMetric(d),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: _header(context, d)),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: context.isMobile ? 1.45 : 1.75,
            ),
            delegate: SliverChildListDelegate(stats),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(child: _charts(context, d)),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(child: _recentSales(context, d)),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(child: _followUps(context, d)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, DashboardSnapshot d) {
    final ShowroomModel? showroom = _session.activeShowroom;
    return AppCard(
      padding: 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_greeting()}, ${_session.displayName}',
                  style: context.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  showroom == null
                      ? 'No showroom selected - showing every showroom you can '
                          'access.'
                      : 'Working in ${showroom.name}'
                          '${showroom.code.isEmpty ? '' : ' (${showroom.code})'}',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (EnvironmentConfig.isDevelopment)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: AppStatusChip(status: 'development'),
                ),
              Text(
                'Updated ${DateUtils.formatDateTime(d.generatedAt)}',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // --------------------------------------------------------------- KPI cards

  Widget _saleMetrics(DashboardSnapshot d) {
    final num change = d.monthOverMonthChange;
    return AppStatCard(
      title: 'Sales this month',
      value: AppFormatters.compactMoney(d.monthSales.total),
      icon: Icons.point_of_sale_outlined,
      caption: '${AppFormatters.number(d.monthSales.count)} completed · '
          '${AppFormatters.compactMoney(d.todaySales.total)} today',
      trend: change == 0
          ? null
          : '${change > 0 ? '+' : ''}${AppFormatters.percent(change)} vs last '
              'month',
      onTap: () => _open(AppRoutes.sales, Permissions.salesView),
    );
  }

  Widget _collectionMetric(DashboardSnapshot d) => AppStatCard(
        title: 'Collected today',
        value: AppFormatters.compactMoney(d.todayCollections.total),
        icon: Icons.payments_outlined,
        caption: '${AppFormatters.number(d.todayCollections.count)} receipts',
        onTap: () => _open(AppRoutes.payments, Permissions.paymentsView),
      );

  Widget _receivableMetric(DashboardSnapshot d) => AppStatCard(
        title: 'Outstanding invoices',
        value: AppFormatters.compactMoney(d.receivables.total),
        color: d.receivables.total > 0 ? const Color(0xFFDC2626) : null,
        icon: Icons.receipt_long_outlined,
        caption: '${AppFormatters.number(d.receivables.count)} unpaid',
        onTap: () => _open(AppRoutes.billing, Permissions.billingView),
      );

  Widget _emiMetric(DashboardSnapshot d) => AppStatCard(
        title: 'EMIs due',
        value: AppFormatters.compactMoney(d.overdueEmis.total),
        color: d.overdueEmis.total > 0 ? const Color(0xFFF59E0B) : null,
        icon: Icons.request_quote_outlined,
        caption: '${AppFormatters.number(d.overdueEmis.count)} due or overdue',
        onTap: () => _open(AppRoutes.loans, Permissions.financeView),
      );

  Widget _jobMetric(DashboardSnapshot d) => AppStatCard(
        title: 'Open job cards',
        value: AppFormatters.number(d.openJobs.count),
        icon: Icons.engineering_outlined,
        caption: 'Awaiting service or delivery',
        onTap: () => _open(AppRoutes.service, Permissions.serviceView),
      );

  Widget _expenseMetric(DashboardSnapshot d) => AppStatCard(
        title: 'Expenses this month',
        value: AppFormatters.compactMoney(d.monthExpenses.total),
        color: d.pendingExpenses.count > 0 ? const Color(0xFF2563EB) : null,
        icon: Icons.account_balance_wallet_outlined,
        caption: '${AppFormatters.number(d.pendingExpenses.count)} awaiting '
            'approval',
        onTap: () => _open(AppRoutes.expenses, Permissions.expensesView),
      );

  Widget _stockMetric(DashboardSnapshot d) => AppStatCard(
        title: 'Ready stock',
        value: AppFormatters.number(d.stockAvailable),
        icon: Icons.inventory_2_outlined,
        caption: '${AppFormatters.number(d.stockReserved)} reserved units',
        onTap: () => _open(AppRoutes.inventory, Permissions.inventoryView),
      );

  Widget _customerMetric(DashboardSnapshot d) => AppStatCard(
        title: 'Recent buyers',
        value: AppFormatters.number(d.recentSales.length),
        icon: Icons.people_alt_outlined,
        caption: 'In the latest sales feed',
        onTap: () => _open(AppRoutes.customers, Permissions.customersView),
      );

  void _open(String route, String permission) {
    if (!_session.can(permission)) {
      Get.toNamed(AppRoutes.forbidden, arguments: permission);
      return;
    }
    Get.toNamed(route);
  }

  // ------------------------------------------------------------------ charts

  Widget _charts(BuildContext context, DashboardSnapshot d) {
    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < d.trend.length; i++)
        FlSpot(i.toDouble(), d.trend[i].amount.toDouble()),
    ];
    final Widget trend = AppCard(
      title: 'Revenue trend',
      subtitle: 'Completed sales, last ${d.trend.length} months',
      child: spots.isEmpty
          ? const SizedBox(height: 160, child: AppLoader(small: true))
          : AppBarChart(
              height: 220,
              xLabels: <String>[for (final DashboardTrendPoint p in d.trend) p.label],
              series: <ChartSeries>[
                ChartSeries(
                  name: 'Revenue',
                  points: spots,
                  color: context.colors.primary,
                ),
              ],
            ),
    );

    final double available = d.stockAvailable.toDouble();
    final double reserved = d.stockReserved.toDouble();
    final Widget stock = AppCard(
      title: 'Stock mix',
      subtitle: 'Units by inventory status',
      child: available + reserved == 0
          ? const SizedBox(
              height: 160,
              child: Center(child: Text('No units in stock')),
            )
          : AppPieChart(
              height: 220,
              slices: <ChartSlice>[
                ChartSlice(label: 'Available', value: available),
                ChartSlice(
                  label: 'Reserved',
                  value: reserved,
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
    );

    if (!context.isDesktop) {
      return Column(children: <Widget>[trend, const SizedBox(height: 16), stock]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 3, child: trend),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: stock),
      ],
    );
  }

  // ----------------------------------------------------------- recent sales

  Widget _recentSales(BuildContext context, DashboardSnapshot d) {
    return AppCard(
      title: 'Recent sales',
      subtitle: 'Latest bookings and deliveries',
      actions: <Widget>[
        if (_session.can(Permissions.salesView))
          AppButton(
            label: 'View all',
            variant: AppButtonVariant.text,
            size: AppButtonSize.small,
            onPressed: () => Get.toNamed(AppRoutes.sales),
          ),
      ],
      child: d.recentSales.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('No sales recorded yet.'),
            )
          : Column(
              children: <Widget>[
                for (final Map<String, dynamic> row in d.recentSales)
                  _saleRow(context, row),
              ],
            ),
    );
  }

  Widget _saleRow(BuildContext context, Map<String, dynamic> row) {
    final String id = SafeJson.asText(row['id']);
    final String number = SafeJson.asText(row['sale_number'], fallback: '-');
    final String status = SafeJson.asText(row['status'], fallback: 'draft');
    final num amount = SafeJson.asMoney(row['total_amount']);
    final DateTime? date = SafeJson.asDay(row['sale_date']);
    final dynamic customer = row['customer'];
    final String customerName = customer is Map
        ? SafeJson.asText(SafeJson.asMap(customer)['name'], fallback: 'Walk-in')
        : 'Walk-in';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: id.isEmpty || !_session.can(Permissions.salesView)
          ? null
          : () => Get.toNamed('${AppRoutes.saleDetails}/$id'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    number,
                    style: context.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$customerName · ${DateUtils.format(date)}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppStatusChip(status: status),
            const SizedBox(width: 12),
            Text(
              AppFormatters.amount(amount),
              style: context.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- follow-ups

  Widget _followUps(BuildContext context, DashboardSnapshot d) {
    final List<_FollowUp> items = <_FollowUp>[
      if (d.overdueEmis.count > 0)
        _FollowUp(
          icon: Icons.request_quote_outlined,
          color: const Color(0xFFDC2626),
          title: '${d.overdueEmis.count} EMI instalment(s) due or overdue',
          subtitle: 'Collect payments or record deferrals',
          route: AppRoutes.loans,
          permission: Permissions.financeView,
        ),
      if (d.pendingExpenses.count > 0)
        _FollowUp(
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF2563EB),
          title: '${d.pendingExpenses.count} expense(s) awaiting approval',
          subtitle: 'Approve or reject with a reason',
          route: AppRoutes.expenses,
          permission: Permissions.expensesApprove,
        ),
      if (d.openJobs.count > 0)
        _FollowUp(
          icon: Icons.engineering_outlined,
          color: const Color(0xFFF59E0B),
          title: '${d.openJobs.count} job card(s) still open',
          subtitle: 'Update progress or deliver the vehicle',
          route: AppRoutes.service,
          permission: Permissions.serviceView,
        ),
      if (d.receivables.count > 0)
        _FollowUp(
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFF9333EA),
          title: '${d.receivables.count} invoice(s) not settled',
          subtitle: 'Send payment reminders to customers',
          route: AppRoutes.billing,
          permission: Permissions.billingView,
        ),
    ];

    final List<Widget> children = <Widget>[
      for (final _FollowUp item in items) item.tile(context, canOpen: _session.can(item.permission)),
      for (final Map<String, dynamic> row in d.upcomingReminders)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_none_rounded),
          title: Text(SafeJson.asText(row['title'], fallback: 'Reminder')),
          subtitle: Text(
            'Due ${DateUtils.format(SafeJson.asDay(row['reminder_date']))}',
          ),
          onTap: _session.can(Permissions.remindersView)
              ? () => Get.toNamed(AppRoutes.reminders)
              : null,
        ),
    ];

    return AppCard(
      title: 'Needs attention',
      subtitle: 'Next 7 days',
      child: children.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Nothing pending - the floor is clear.'),
            )
          : Column(
              children: children
                  .map(
                    (Widget child) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: child,
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _FollowUp {
  const _FollowUp({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.permission,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;
  final String permission;

  Widget tile(BuildContext context, {required bool canOpen}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: context.textTheme.bodyMedium),
      subtitle: Text(subtitle, style: context.textTheme.bodySmall),
      trailing: canOpen
          ? Icon(
              Icons.chevron_right,
              color: context.colors.onSurfaceVariant,
            )
          : null,
      onTap: canOpen ? () => Get.toNamed(route) : null,
    );
  }
}
