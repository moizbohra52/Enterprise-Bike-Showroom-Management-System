import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';

/// Shows and lets the user switch the active (working) showroom.
/// SUPER ADMIN sees all showrooms; others only their assignments.
class ShowroomSelector extends StatelessWidget {
  const ShowroomSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionController session = Get.find<SessionController>();
    return Obx(() {
      final showrooms = session.accessibleShowrooms;
      if (showrooms.isEmpty) return const SizedBox.shrink();
      final options = <DropdownOption<String>>[
        for (final s in showrooms)
          DropdownOption<String>(value: s.id ?? '', label: s.name),
      ];
      return DropdownButtonHideUnderline(
        child: Tooltip(
          message: 'Switch showroom',
          child: DropdownButton<String>(
            value: options.any((DropdownOption<String> o) =>
                    o.value == session.activeShowroomId)
                ? session.activeShowroomId
                : null,
            hint: const Text('Showroom…',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            borderRadius: BorderRadius.circular(10),
            isDense: true,
            dropdownColor: Theme.of(context).canvasColor,
            icon: const Icon(Icons.swap_vert, size: 16),
            items: <DropdownMenuItem<String>>[
              for (final DropdownOption<String> o in options)
                DropdownMenuItem<String>(value: o.value, child: Text(o.label)),
            ],
            onChanged: session.isSuperAdmin || options.length > 1
                ? (String? id) async {
                    if (id == null || id == session.activeShowroomId) return;
                    try {
                      await session.setActiveShowroom(id);
                      AppSnackbar.success(context, 'Showroom switched');
                    } on AppException catch (e) {
                      AppSnackbar.error(context, e.message);
                    } catch (e) {
                      AppSnackbar.error(context, ErrorMapper.friendly(e));
                    }
                  }
                : null,
          ),
        ),
      );
    });
  }
}
