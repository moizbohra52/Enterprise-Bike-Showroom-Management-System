import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/controllers/vehicle_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/models/customer_models.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Vehicle 360 — a customer vehicle with its complete history.
class VehicleDetailsView extends GetView<VehicleDetailsController> {
  const VehicleDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Vehicle', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Vehicle 360',
      showBack: true,
      actions: <Widget>[
        if (session.can(Permissions.serviceCreate))
          AppButton(
            label: 'New Service',
            icon: Icons.engineering,
            variant: AppButtonVariant.outlined,
            onPressed: () => Get.toNamed(AppRoutes.serviceForm,
                parameters: <String, String?>{'vehicleId': id}),
          ),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.vehicle.value == null) {
          return const AppLoader();
        }
        final CustomerVehicleModel v = controller.vehicle.value!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              _VehicleHeader(vehicle: v),
              const SizedBox(height: 12),
              _VehicleKpis(vehicle: v),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Service History',
                rows: controller.services.value,
                dateField: 'service_date',
                numberField: 'service_number',
                amountField: 'total_amount',
                emptyTitle: 'No services yet',
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Warranty',
                rows: controller.warranties.value,
                dateField: 'start_date',
                numberField: null,
                amountField: null,
                emptyTitle: 'No warranty records',
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Insurance',
                rows: controller.insurance.value,
                dateField: 'start_date',
                numberField: 'policy_number',
                amountField: 'premium',
                emptyTitle: 'No insurance on record',
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Reminders',
                rows: controller.reminders.value,
                dateField: 'reminder_date',
                numberField: null,
                amountField: null,
                emptyTitle: 'No reminders',
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }

  String? _pathId() {
    final String? name = Get.currentRoute;
    if (name != null) {
      final List<String> parts = name.split('/');
      if (parts.isNotEmpty) return parts.last;
    }
    return null;
  }
}

class _VehicleHeader extends StatelessWidget {
  const _VehicleHeader({required this.vehicle});

  final CustomerVehicleModel vehicle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: vehicle.productLabel,
      subtitle: 'Reg No. ${vehicle.registrationNumber}',
      actions: <Widget>[AppStatusChip(status: vehicle.status)],
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: <Widget>[
          _kv('Chassis', vehicle.chassisNumber),
          _kv('Engine', vehicle.engineNumber),
          _kv('Purchased', AppFormatters.date(vehicle.purchaseDate)),
          _kv('Delivered', AppFormatters.date(vehicle.deliveryDate)),
          _kv('Reg. Date', AppFormatters.date(vehicle.registrationDate)),
          _kv('Odometer', AppFormatters.km(vehicle.currentOdometer)),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _VehicleKpis extends GetView<VehicleDetailsController> {
  @override
  Widget build(BuildContext context) {
    final CustomerVehicleModel v = controller.vehicle.value!;
    return Row(
      children: <Widget>[
        Expanded(
          child: AppStatCard(
            title: 'Warranty',
            value: controller.warrantyActive ? 'Active' : 'Expired',
  caption: controller.warrantySummary,
            icon: Icons.verified_user,
            color: controller.warrantyActive
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppStatCard(
            title: 'Insurance',
            value: (v.insuranceEnd == null || v.insuranceEnd!.isAfter(DateTime.now())) &&
                    v.insuranceStart != null
                ? 'Active'
                : 'Lapsed',
  caption:
                '${AppFormatters.date(v.insuranceStart)} → ${AppFormatters.date(v.insuranceEnd)}',
            icon: Icons.policy,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppStatCard(
            title: 'Next Service',
            value: AppFormatters.date(v.nextServiceDate),
  caption: v.nextServiceKm == null ? '' : 'at ${AppFormatters.km(v.nextServiceKm!)}',
            icon: Icons.engineering,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppStatCard(
            title: 'Services Done',
            value: '${controller.services.value.length}',
            icon: Icons.build_outlined,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.rows,
    required this.dateField,
    required this.numberField,
    required this.amountField,
    required this.emptyTitle,
    this.onRowTap,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String dateField;
  final String? numberField;
  final String? amountField;
  final String emptyTitle;
  final void Function(String rowId)? onRowTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: title,
      child: rows.isEmpty
          ? AppEmptyState(icon: Icons.inbox_outlined, title: emptyTitle)
          : Column(
              children: <Widget>[
                for (final Map<String, dynamic> row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        onTap: onRowTap == null
                            ? null
                            : () => onRowTap!(row['id']?.toString() ?? ''),
                        title: Text(
                          numberField == null
                              ? '${row['id']?.toString() ?? 'Record'}'
                              : row[numberField]?.toString() ?? '',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _describe(row),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        isThreeLine: true,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _describe(Map<String, dynamic> row) {
    final StringBuffer buffer = StringBuffer();
    buffer.write(AppFormatters.date(row[dateField]));
    if (amountField != null) {
      buffer.write(
          '  ·  ${AppFormatters.currency(double.tryParse(row[amountField]?.toString() ?? '') ?? 0)}');
    }
    final String? status = row['status']?.toString();
    if (status != null) buffer.write('  ·  ${AppFormatters.humanize(status)}');
    return buffer.toString();
  }
}
