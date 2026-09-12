import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dialog.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/controllers/customer_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/models/customer_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Customer 360 — complete customer dashboard.
class CustomerDetailsView extends GetView<CustomerDetailsController> {
  const CustomerDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'];
    if (id == null) {
      return AppShell(
          title: 'Customer', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Customer 360',
      showBack: true,
      actions: <Widget>[
        if (session.can(Permissions.salesCreate))
          AppButton(
            label: 'New Sale',
            icon: Icons.point_of_sale,
            variant: AppButtonVariant.outlined,
            onPressed: () => Get.toNamed(AppRoutes.saleForm,
                parameters: <String, String?>{'customerId': id}),
          ),
        if (session.can(Permissions.customersEdit))
          const SizedBox(width: 8),
        if (session.can(Permissions.customersEdit))
          AppButton(
            label: 'Edit',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.outlined,
            onPressed: () async {
              final CustomerController list = Get.find<CustomerController>();
              await list.openForm(id: id);
              controller.load(id);
            },
          ),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.customer.value == null) {
          return const AppLoader();
        }
        final CustomerModel customer = controller.customer.value!;
        return Column(
          children: <Widget>[
            _KpiRow(customer: customer),
            Expanded(
              child: DefaultTabController(
                length: 12,
                child: Column(
                  children: <Widget>[
                    TabBar(
                      isScrollable: true,
                      labelStyle: const TextStyle(fontSize: 13),
                      tabs: const <Widget>[
                        Tab(text: 'Profile'),
                        Tab(text: 'Vehicles'),
                        Tab(text: 'Sales'),
                        Tab(text: 'Invoices'),
                        Tab(text: 'Payments'),
                        Tab(text: 'EMIs'),
                        Tab(text: 'Services'),
                        Tab(text: 'Warranty'),
                        Tab(text: 'Insurance'),
                        Tab(text: 'Reminders'),
                        Tab(text: 'Documents'),
                        Tab(text: 'Timeline'),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: TabBarView(
                        children: <Widget>[
                          _ProfileTab(customer: customer),
                          _VehiclesTab(),
                          _RecordsTab(title: 'Sales', rows: controller.sales.value,
                              dateField: 'sale_date', amountField: 'total_amount',
                              numberField: 'sale_number',
                              onRowTap: (String rowId) => Get.toNamed(
                                  '${AppRoutes.saleDetails}/$rowId')),
                          _RecordsTab(title: 'Invoices', rows: controller.invoices.value,
                              dateField: 'invoice_date', amountField: 'total_amount',
                              numberField: 'invoice_number',
                              onRowTap: (String rowId) => Get.toNamed(
                                  '${AppRoutes.invoiceDetails}/$rowId')),
                          _RecordsTab(title: 'Payments', rows: controller.payments.value,
                              dateField: 'payment_date', amountField: 'amount',
                              numberField: 'payment_number',
                              onRowTap: (String rowId) => Get.toNamed(
                                  '${AppRoutes.paymentDetails}/$rowId')),
                          _RecordsTab(title: 'EMI Schedule', rows: controller.emiRows.value,
                              dateField: 'due_date', amountField: 'emi_amount',
                              numberField: null),
                          _RecordsTab(title: 'Services', rows: controller.services.value,
                              dateField: 'service_date', amountField: 'total_amount',
                              numberField: 'service_number',
                              onRowTap: (String rowId) => Get.toNamed(
                                  '${AppRoutes.serviceDetails}/$rowId')),
                          _RecordsTab(title: 'Warranties', rows: controller.warranties.value,
                              dateField: 'start_date', amountField: null,
                              numberField: null),
                          _RecordsTab(title: 'Insurance', rows: controller.insurance.value,
                              dateField: 'start_date', amountField: 'premium',
                              numberField: 'policy_number'),
                          _RecordsTab(title: 'Reminders', rows: controller.reminders.value,
                              dateField: 'reminder_date', amountField: null,
                              numberField: null),
                          _RecordsTab(title: 'Documents', rows: controller.documents.value,
                              dateField: 'created_at', amountField: null,
                              numberField: 'file_name'),
                          _TimelineTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.customer});

  final CustomerModel customer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: AppStatCard(
              title: 'Outstanding',
              value: Get.find<CustomerDetailsController>().outstanding.value.currency,
              icon: Icons.account_balance_outlined,
              color: const Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppStatCard(
              title: 'Vehicles',
              value: '${customer.vehicleCount}',
              icon: Icons.directions_bike,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppStatCard(
              title: 'Since',
              value: AppFormatters.date(customer.createdAt),
              icon: Icons.event_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppStatCard(
              title: 'Code',
              value: customer.customerCode,
              icon: Icons.badge_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.customer});

  final CustomerModel customer;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AppCard(
        title: customer.name,
        subtitle: customer.fullAddress,
        actions: <Widget>[AppStatusChip(status: customer.status)],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _row('Code', customer.customerCode, bold: true),
            _row('Phone', AppFormatters.phone(customer.phone)),
            _row('Alternate Phone', AppFormatters.phone(customer.alternatePhone)),
            _row('Email', customer.email),
            _row('Type', AppFormatters.humanize(customer.customerType)),
            _row('Notes', customer.notes.isEmpty ? '-' : customer.notes),
            _row('Created', AppFormatters.dateTime(customer.createdAt)),
            _row('Updated', AppFormatters.dateTime(customer.updatedAt)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehiclesTab extends GetView<CustomerDetailsController> {
  const _VehiclesTab();

  @override
  Widget build(BuildContext context) {
    final List<CustomerVehicleModel> vehicles = controller.vehicles.value;
    if (vehicles.isEmpty) {
      return const AppEmptyState(
        icon: Icons.directions_bike,
        title: 'No vehicles',
        message: 'Vehicles appear here after a sale is completed.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final CustomerVehicleModel v = vehicles[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => Get.toNamed(AppRoutes.withId(AppRoutes.vehicleDetails, v.id!)),
            leading: const Icon(Icons.directions_bike),
            title: Text(v.productLabel),
            subtitle: Text(
              'Reg ${v.registrationNumber} · Chassis ${v.chassisNumber}\n'
              'Odo ${AppFormatters.km(v.currentOdometer)} · '
              'Next service ${AppFormatters.date(v.nextServiceDate)}',
              maxLines: 2,
            ),
            isThreeLine: true,
            trailing: AppStatusChip(status: v.status),
          ),
        );
      },
    );
  }
}

/// Generic read-only record table for customer tabs.
class _RecordsTab extends StatelessWidget {
  const _RecordsTab({
    required this.title,
    required this.rows,
    required this.dateField,
    required this.amountField,
    this.numberField,
    this.onRowTap,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String dateField;
  final String? amountField;
  final String? numberField;
  final void Function(String rowId)? onRowTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (rows.isEmpty) {
      return AppEmptyState(icon: Icons.table_rows_outlined, title: 'No $title yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Map<String, dynamic> row = rows[index];
        final String? rowId = row['id']?.toString();
        final String number = numberField == null ? '' : row[numberField]?.toString() ?? '';
        final String date = row[dateField]?.toString() ?? '';
        final String amount =
            amountField == null ? '' : AppFormatters.currency(_money(row[amountField]));
        final String? status = row['status']?.toString();
        return Card(
          child: ListTile(
            onTap: (onRowTap != null && rowId != null) ? () => onRowTap!(rowId) : null,
            title: Text(number.isEmpty ? (rowId ?? 'Record') : number,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: amount.isEmpty
                ? null
                : Text('$date · $amount', style: theme.textTheme.bodySmall),
            trailing: status == null ? null : AppStatusChip(status: status),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  double _money(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
}

class _TimelineTab extends GetView<CustomerDetailsController> {
  const _TimelineTab();

  static const Map<String, IconData> _icons = <String, IconData>{
    'sale': Icons.point_of_sale,
    'invoice': Icons.receipt_long,
    'payment': Icons.payments,
    'loan': Icons.account_balance,
    'emi': Icons.request_quote,
    'service': Icons.engineering,
    'warranty': Icons.verified_user,
    'insurance': Icons.policy,
    'reminder': Icons.notifications,
  };

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> events = controller.timeline.value;
    if (events.isEmpty) {
      return const AppEmptyState(
          icon: Icons.timeline, title: 'No activity yet');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (BuildContext context, int index) {
        final Map<String, dynamic> event = events[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                _icons[event['type']?.toString()] ?? Icons.circle,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(event['label']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                      AppFormatters.date(event['date']) +
                          (event['amount'] != null
                              ? '  ·  ${AppFormatters.currency(_money(event['amount']))}'
                              : ''),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _money(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;
}
