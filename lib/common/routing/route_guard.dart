import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/auth/views/forbidden_view.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Session/permission gate used by every protected page in `AppPages`.
///
/// The check is reactive: if the session disappears (logout, token revoked)
/// while a page is open, the user is returned to the login screen. Permission
/// enforcement here is UI-level only - the real boundary is Supabase RLS.
class RouteGuard extends StatefulWidget {
  const RouteGuard({
    super.key,
    required this.child,
    this.permission,
    this.allowUnauthenticated = false,
  });

  final Widget child;

  /// Required `module.action` (null = authentication only).
  final String? permission;

  /// True for the auth screens (splash/login/reset).
  final bool allowUnauthenticated;

  @override
  State<RouteGuard> createState() => _RouteGuardState();
}

class _RouteGuardState extends State<RouteGuard> {
  bool _redirectScheduled = false;

  /// Schedules at most one navigation to the login screen per frame.
  void _toLogin() {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    AppLogger.warning(
      'ROUTE',
      'unauthenticated access to ${Get.currentRoute} -> login',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirectScheduled = false;
      if (!mounted) return;
      if (Get.currentRoute == AppRoutes.login) return;
      Get.offAllNamed(AppRoutes.login);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allowUnauthenticated) return widget.child;
    final SessionController session = Get.find<SessionController>();
    return Obx(() {
      // Auth state + profile still loading - hold the page.
      if (!session.isAuthReady.value) {
        return const AppLoader(message: 'Restoring session…');
      }
      if (!session.isAuthenticated) {
        _toLogin();
        return const AppLoader(message: 'Signing you in…');
      }
      final String? permission = widget.permission;
      if (permission != null && !session.can(permission)) {
        return ForbiddenView(permission: permission, inline: true);
      }
      return widget.child;
    });
  }
}
