import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/payments/controllers/payment_controller.dart';
import 'package:enterprise_bike_showroom/features/payments/repositories/payment_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers payment module dependencies.
class PaymentBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PaymentRepository>(
      () => PaymentRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<PaymentController>(
      () => PaymentController(Get.find<PaymentRepository>()),
      fenix: true,
    );
    Get.lazyPut<PaymentFormController>(
      () => PaymentFormController(
        Get.find<PaymentRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
    Get.lazyPut<PaymentDetailsController>(
      () => PaymentDetailsController(Get.find<PaymentRepository>()),
      fenix: true,
    );
  }
}
