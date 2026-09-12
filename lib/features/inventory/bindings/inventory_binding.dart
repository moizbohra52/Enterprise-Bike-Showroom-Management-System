import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/inventory/controllers/inventory_controller.dart';
import 'package:enterprise_bike_showroom/features/inventory/repositories/inventory_repository.dart';

/// Registers inventory module dependencies.
class InventoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<InventoryRepository>(
      () => InventoryRepository(Get.find()),
      fenix: true,
    );
    Get.lazyPut<InventoryController>(
      () => InventoryController(Get.find<InventoryRepository>()),
      fenix: true,
    );
    Get.lazyPut<InventoryDetailsController>(
      () => InventoryDetailsController(Get.find<InventoryRepository>()),
      fenix: true,
    );
  }
}
