import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_error_state.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shown when a route guard denies access (missing permission).
class ForbiddenView extends StatelessWidget {
  const ForbiddenView({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionController session = Get.find<SessionController>();
    return AppShell(
      title: 'Access denied',
      child: AppErrorState(
        icon: Icons.lock_outline,
        message: 'Your role does not include the permission required for '
            'this screen.\nSigned in as ${session.displayName} '
            '(${session.roleNames.isEmpty ? 'no role' : session.roleNames.join(', ')}).',
        onRetry: () => Get.offAllNamed(AppRoutes.dashboard),
      ),
    );
  }
}
