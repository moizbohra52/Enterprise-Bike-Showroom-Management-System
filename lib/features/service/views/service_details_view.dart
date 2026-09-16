import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dialog.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/service/controllers/service_controller.dart';
import 'package:enterprise_bike_showroom/features/service/models/service_models.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// Job card details + complete (delivery) + status actions.
class ServiceDetailsView extends GetView<ServiceDetailsController> {
  const ServiceDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Service', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Job Card',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final ServiceRecordModel? service = controller.service.value;
          if (service == null || !session.can(Permissions.serviceComplete)) {
            return const SizedBox.shrink();
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (service.status != 'delivered' &&
                  service.status != 'cancelled')
                AppButton(
                  label: 'Complete & Deliver',
                  icon: Icons.check_circle_outline,
                  onPressed: () => _complete(context),
                ),
            ],
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.service.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(context, controller.service.value!),
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

  Future<void> _complete(BuildContext context) async {
    final ServiceRecordModel service = controller.service.value!;
    final num? odIn = service.odometerIn;
    final String? od = await AppDialog.prompt(
      context,
      title: 'Complete job card',
      message: 'Odometer in: ${odIn ?? 0}\n'
          'Enter odometer out (km):',
      confirmLabel: 'Complete',
      keyboardType: TextInputType.number,
    );
    if (od == null) return;
    final num odOut = double.tryParse(od) ?? 0;
    final String? work = await AppDialog.prompt(
      context,
      title: 'Work done',
      message: 'Describe the work performed:',
      confirmLabel: 'Continue',
      hint: 'Work summary',
      maxLines: 3,
    );
    if (work == null) return;
    final bool ok = await controller.complete(
        odometerOut: odOut, workDone: work);
    if (ok) AppSnackbar.success(context, 'Vehicle delivered');
  }

  Widget _body(BuildContext context, ServiceRecordModel service) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(service.serviceNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${service.customerName} · ${service.vehicleLabel} · '
                    '${AppFormatters.date(service.serviceDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(status: service.status),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: service.jobType == 'paid'
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                AppFormatters.humanize(service.jobType).toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Total',
                  value: service.totalAmount.currency,
                  icon: Icons.build_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Collected',
                  value: service.paidAmount.currency,
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Odo In → Out',
                  value: '${service.odometerIn?.toStringAsFixed(0) ?? '-'} → '
                      '${service.odometerOut?.toStringAsFixed(0) ?? '-'}',
                  icon: Icons.speed),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Items',
          child: Column(
            children: <Widget>[
              for (final ServiceItemModel item in service.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(item.name,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text(
                          '${item.qty} × ${item.unitPrice.currency} '
                          '(${AppFormatters.humanize(item.itemType)})',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 24),
                      Text(item.totalAmount.currency,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (service.problemDescription.isNotEmpty)
          _textCard('Problem', service.problemDescription),
        if (service.workDone.isNotEmpty)
          _textCard('Work done', service.workDone),
      ],
    );
  }

  Widget _textCard(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        title: title,
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
