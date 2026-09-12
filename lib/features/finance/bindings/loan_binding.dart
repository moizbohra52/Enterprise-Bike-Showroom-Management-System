import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/finance/controllers/loan_controller.dart';
import 'package:enterprise_bike_showroom/features/finance/repositories/loan_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers finance (loan / EMI) module dependencies.
class LoanBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LoanRepository>(
      () => LoanRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<LoanController>(
      () => LoanController(Get.find<LoanRepository>()),
      fenix: true,
    );
    Get.lazyPut<LoanDetailsController>(
      () => LoanDetailsController(Get.find<LoanRepository>()),
      fenix: true,
    );
  }
}
