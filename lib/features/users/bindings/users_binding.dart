import 'package:enterprise_bike_showroom/features/users/repositories/user_repository.dart';
import 'package:enterprise_bike_showroom/features/users/controllers/user_form_controller.dart';
import 'package:enterprise_bike_showroom/features/users/controllers/users_controller.dart';
import 'package:get/get.dart';

/// Registers the users & roles administration controllers.
class UsersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UserRepository>(() => UserRepository(Get.find()), fenix: true);
    Get.lazyPut<UsersController>(
      () => UsersController(Get.find<UserRepository>(), Get.find()),
      fenix: true,
    );
    Get.lazyPut<UserFormController>(
      () => UserFormController(Get.find<UserRepository>(), Get.find()),
      fenix: true,
    );
  }
}
