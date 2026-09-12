import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/insurance/controllers/insurance_controller.dart';
import 'package:enterprise_bike_showroom/features/insurance/repositories/insurance_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers insurance module dependencies.
class InsuranceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<InsuranceRepository>(
      () => InsuranceRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<InsuranceController>(
      () => InsuranceController(Get.find<InsuranceRepository>()),
      fenix: true,
    );
    Get.lazyPut<InsuranceFormController>(
      () => InsuranceFormController(
        Get.find<InsuranceRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
    Get.lazyPut<InsuranceDetailsController>(
      () => InsuranceDetailsController(Get.find<InsuranceRepository>()),
      fenix: true,
    );
  }
}
