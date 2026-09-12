import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/freeservice/controllers/free_service_controller.dart';
import 'package:enterprise_bike_showroom/features/freeservice/repositories/free_service_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers free-service module dependencies.
class FreeServiceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<FreeServiceRepository>(
      () => FreeServiceRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<FreeServiceController>(
      () => FreeServiceController(Get.find<FreeServiceRepository>()),
      fenix: true,
    );
  }
}
