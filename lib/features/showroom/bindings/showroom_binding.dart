import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/showroom/controllers/showroom_controller.dart';
import 'package:enterprise_bike_showroom/features/showroom/repositories/showroom_repository.dart';

/// Registers showroom module dependencies.
class ShowroomBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ShowroomRepository>(
      () => ShowroomRepository(Get.find()),
      fenix: true,
    );
    Get.lazyPut<ShowroomController>(
      () => ShowroomController(Get.find<ShowroomRepository>(), Get.find()),
      fenix: true,
    );
  }
}
