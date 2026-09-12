import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/warranty/controllers/warranty_controller.dart';
import 'package:enterprise_bike_showroom/features/warranty/repositories/warranty_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers warranty module dependencies.
class WarrantyBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<WarrantyRepository>(
      () => WarrantyRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<WarrantyController>(
      () => WarrantyController(Get.find<WarrantyRepository>()),
      fenix: true,
    );
    Get.lazyPut<WarrantyDetailsController>(
      () => WarrantyDetailsController(Get.find<WarrantyRepository>()),
      fenix: true,
    );
  }
}
