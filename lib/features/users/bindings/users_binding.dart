import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/users/controllers/user_form_controller.dart';
import 'package:enterprise_bike_showroom/features/users/controllers/users_controller.dart';
import 'package:enterprise_bike_showroom/features/users/repositories/user_repository.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';

/// Registers the users & roles administration controllers.
///
/// `SessionController` and `AuthService` are global (registered permanently by
/// `InitialBinding`), so `Get.find` resolves them here.
class UsersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UserRepository>(() => UserRepository(Get.find()), fenix: true);
    Get.lazyPut<UsersController>(
      () => UsersController(Get.find<UserRepository>(), Get.find()),
      fenix: true,
    );
    Get.lazyPut<UserFormController>(
      () => UserFormController(
        Get.find<UserRepository>(),
        Get.find<SessionController>(),
        Get.find<AuthService>(),
      ),
      fenix: true,
    );
  }
}
