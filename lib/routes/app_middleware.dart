import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Redirects unauthenticated navigation to the login screen.
///
/// While the session is still bootstrapping (`isAuthReady == false`) the
/// middleware stays out of the way so the splash screen can finish restoring
/// the persisted session.
class AuthMiddleware extends GetMiddleware {
  @override
  int get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    if (!Get.isRegistered<SessionController>()) return null;
    final SessionController session = Get.find<SessionController>();
    if (!session.isAuthReady.value) return null;
    if (session.isAuthenticated) return null;
    return const RouteSettings(name: AppRoutes.login);
  }
}

/// Requires a `module.action` permission on top of [AuthMiddleware].
///
/// Denials land on [AppRoutes.forbidden] instead of silently rendering an
/// empty page. Server-side RLS remains the real enforcement boundary.
class PermissionMiddleware extends GetMiddleware {
  PermissionMiddleware(this.permission);

  /// Permission string, e.g. `users.view`.
  final String permission;

  @override
  int get priority => 2;

  @override
  RouteSettings? redirect(String? route) {
    if (!Get.isRegistered<SessionController>()) return null;
    final SessionController session = Get.find<SessionController>();
    if (!session.isAuthReady.value) return null;
    if (!session.isAuthenticated) {
      return const RouteSettings(name: AppRoutes.login);
    }
    if (session.can(permission)) return null;
    return const RouteSettings(name: AppRoutes.forbidden);
  }
}
