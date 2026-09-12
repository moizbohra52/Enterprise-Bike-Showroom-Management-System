import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/purchases/controllers/purchase_controller.dart';
import 'package:enterprise_bike_showroom/features/purchases/repositories/purchase_repository.dart';
import 'package:enterprise_bike_showroom/features/products/repositories/product_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers purchase / supplier module dependencies.
class PurchaseBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PurchaseRepository>(
      () => PurchaseRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<ProductRepository>(
      () => ProductRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<SupplierController>(
      () => SupplierController(Get.find<PurchaseRepository>()),
      fenix: true,
    );
    Get.lazyPut<PurchaseController>(
      () => PurchaseController(Get.find<PurchaseRepository>()),
      fenix: true,
    );
    Get.lazyPut<PurchaseFormController>(
      () => PurchaseFormController(
        Get.find<PurchaseRepository>(),
        Get.find<SessionController>(),
        Get.find<ProductRepository>(),
      ),
      fenix: true,
    );
    Get.lazyPut<PurchaseDetailsController>(
      () => PurchaseDetailsController(Get.find<PurchaseRepository>()),
      fenix: true,
    );
  }
}
