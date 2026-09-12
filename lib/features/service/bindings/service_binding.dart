import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/service/controllers/service_controller.dart';
import 'package:enterprise_bike_showroom/features/service/repositories/service_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers service (workshop) module dependencies.
class ServiceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ServiceRepository>(
      () => ServiceRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<ServiceController>(
      () => ServiceController(Get.find<ServiceRepository>()),
      fenix: true,
    );
    Get.lazyPut<ServiceFormController>(
      () => ServiceFormController(
        Get.find<ServiceRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
    Get.lazyPut<ServiceDetailsController>(
      () => ServiceDetailsController(Get.find<ServiceRepository>()),
      fenix: true,
    );
  }
}
