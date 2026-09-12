import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_status_chip.dart';
import 'package:enterprise_bike_showroom/common/widgets/future_cache.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/features/showroom/controllers/showroom_controller.dart';

/// Showroom details (profile + settings summary).
class ShowroomDetailsView extends GetView<ShowroomController> {
  const ShowroomDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'];
    if (id == null) {
      return AppShell(title: 'Showroom', showBack: true, child: const AppLoader());
    }
    return AppShell(
      title: 'Showroom Details',
      showBack: true,
      actions: <Widget>[
        AppButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          variant: AppButtonVariant.outlined,
          onPressed: () => controller.openForm(id: id),
        ),
      ],
      child: FutureCache<ShowroomModel?>(
        future: () => controller.repository.getById(id),
        builder: (BuildContext context, AsyncSnapshot<ShowroomModel?> snapshot) {
          if (!snapshot.hasData) {
            return const AppLoader();
          }
          final ShowroomModel s = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppCard(
                  title: s.name,
                  subtitle: s.fullAddress.isEmpty ? null : s.fullAddress,
                  actions: <Widget>[AppStatusChip(status: s.status)],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _row('Code', s.code, bold: true),
                      _row('Phone', AppFormatters.phone(s.phone)),
                      _row('Email', s.email),
                      _row('GST Number', s.gstNumber),
                      _row('PAN Number', s.panNumber),
                      _row('Invoice Prefix', s.invoicePrefix),
                      _row('Created', AppFormatters.date(s.createdAt)),
                      _row('Updated', AppFormatters.date(s.updatedAt)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                  fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}
