import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/sales/controllers/sale_controller.dart';
import 'package:enterprise_bike_showroom/features/sales/repositories/sale_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers sale module dependencies.
class SaleBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SaleRepository>(
      () => SaleRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<SaleController>(
      () => SaleController(Get.find<SaleRepository>()),
      fenix: true,
    );
    Get.lazyPut<SaleFormController>(
      () => SaleFormController(
        Get.find<SaleRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
    Get.lazyPut<SaleDetailsController>(
      () => SaleDetailsController(Get.find<SaleRepository>()),
      fenix: true,
    );
  }
}
