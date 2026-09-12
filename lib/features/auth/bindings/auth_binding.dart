import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';

/// Registers the auth form controller.
///
/// `AuthService` itself is a permanent singleton created by `AppBootstrap`
/// (the session stream must outlive individual routes), so this binding only
/// wires the per-screen form state.
class AuthBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AuthController>(
      () => AuthController(Get.find<AuthService>()),
      fenix: true,
    );
  }
}
