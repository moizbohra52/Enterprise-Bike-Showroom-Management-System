import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_stat_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/insurance/controllers/insurance_controller.dart';
import 'package:enterprise_bike_showroom/features/insurance/models/insurance_models.dart';

/// Insurance policy details.
class InsuranceDetailsView extends GetView<InsuranceDetailsController> {
  const InsuranceDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Insurance', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));

    return AppShell(
      title: 'Policy Details',
      showBack: true,
      child: Obx(() {
        if (controller.isLoading.value || controller.policy.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(controller.policy.value!),
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

  Widget _body(InsurancePolicyModel policy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(policy.policyNumber.isEmpty ? 'Policy' : policy.policyNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${policy.vehicleLabel} · ${policy.customerName} · '
                    '${policy.insurer}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(status: policy.status),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Type',
                  value: AppFormatters.humanize(policy.policyType),
                  icon: Icons.category_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Premium',
                  value: policy.premium.currency,
                  icon: Icons.payments_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Coverage',
                  value: policy.coverageAmount.currency,
                  icon: Icons.verified_user),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Term',
          child: Column(
            children: <Widget>[
              _row('Start', AppFormatters.date(policy.startDate)),
              _row('End', AppFormatters.date(policy.endDate)),
              _row(
                  'Renewal reminder sent',
                  policy.renewalReminderSent ? 'Yes' : 'No'),
              _row('Recorded', AppFormatters.dateTime(policy.createdAt)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
