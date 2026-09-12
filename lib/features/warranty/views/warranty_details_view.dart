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
import 'package:enterprise_bike_showroom/features/warranty/controllers/warranty_controller.dart';
import 'package:enterprise_bike_showroom/features/warranty/models/warranty_models.dart';

/// Warranty details + claims.
class WarrantyDetailsView extends GetView<WarrantyDetailsController> {
  const WarrantyDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Warranty', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));
    final SessionController session = Get.find<SessionController>();

    return AppShell(
      title: 'Warranty Details',
      showBack: true,
      actions: <Widget>[
        Obx(() {
          final WarrantyModel? warranty = controller.warranty.value;
          if (warranty == null ||
              warranty.status != 'active' ||
              !session.can(Permissions.warrantyEdit)) {
            return const SizedBox.shrink();
          }
          return AppButton(
            label: 'Raise Claim',
            icon: Icons.report_outlined,
            onPressed: _raiseClaim,
          );
        }),
      ],
      child: Obx(() {
        if (controller.isLoading.value || controller.warranty.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(),
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

  Future<void> _raiseClaim() async {
    final WarrantyModel warranty = controller.warranty.value!;
    final String? description = await AppDialog.prompt(
      context,
      title: 'Raise warranty claim',
      message: 'Describe the problem for ${warranty.warrantyNumber}:',
      confirmLabel: 'Submit Claim',
      hint: 'Problem description',
      maxLines: 4,
    );
    if (description == null) return;
    final bool ok = await controller.raiseClaim(description);
    if (ok) AppSnackbar.success(context, 'Claim submitted');
  }

  Widget _body() {
    final WarrantyModel warranty = controller.warranty.value!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(warranty.warrantyNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${warranty.vehicleLabel} · ${warranty.customerName} · '
                    '${AppFormatters.humanize(warranty.type)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppStatusChip(status: warranty.status),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                  title: 'Valid',
                  value: '${AppFormatters.date(warranty.startDate)} → '
                      '${AppFormatters.date(warranty.endDate)}',
                  icon: Icons.event),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Mileage limit',
                  value: warranty.mileageLimit > 0
                      ? AppFormatters.km(warranty.mileageLimit)
                      : 'No limit',
                  icon: Icons.speed),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  title: 'Claims',
                  value: '${warranty.claimsCount}',
                  icon: Icons.report_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (warranty.coverage.isNotEmpty)
          _textCard('Coverage', warranty.coverage),
        if (warranty.exclusions.isNotEmpty)
          _textCard('Exclusions', warranty.exclusions),
        AppCard(
          title: 'Claims',
          child: Obx(() {
            final List<WarrantyClaimModel> claims = controller.claims.value;
            if (claims.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No claims raised.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
              );
            }
            return Column(
              children: <Widget>[
                for (final WarrantyClaimModel claim in claims)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(claim.claimNumber,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(claim.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall),
                              if (claim.decisionNotes.isNotEmpty)
                                Text(claim.decisionNotes,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall),
                            ],
                          ),
                        ),
                        AppStatusChip(status: claim.status),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _textCard(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(title: title, child: Text(text,
          style: const TextStyle(fontSize: 13))),
    );
  }
}
