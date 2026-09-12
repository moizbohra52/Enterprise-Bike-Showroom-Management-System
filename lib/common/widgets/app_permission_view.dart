import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';

/// Hides [child] when the signed-in user lacks [permission].
///
/// UI-level guard only - the real enforcement lives in Supabase RLS and
/// database functions.
class AppPermissionView extends StatelessWidget {
  const AppPermissionView({
    super.key,
    required this.permission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  /// `module.action` permission string.
  final String permission;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final SessionController session = Get.find<SessionController>();
    return Obx(() {
      final bool allowed = session.can(permission);
      return allowed ? child : fallback;
    });
  }
}
