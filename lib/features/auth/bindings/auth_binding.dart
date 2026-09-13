import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:get/get.dart';

/// Registers the auth module's form controller.
///
/// [SessionController] is global (registered by `InitialBinding`) because the
/// app shell, route guards and every permission check depend on it.
class AuthBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<AuthController>()) {
      Get.lazyPut<AuthController>(
        () => AuthController(Get.find()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<SessionController>()) {
      throw StateError(
        'SessionController must be registered before the auth routes are used.',
      );
    }
  }
}
