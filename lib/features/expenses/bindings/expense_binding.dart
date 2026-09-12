import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/expenses/controllers/expense_controller.dart';
import 'package:enterprise_bike_showroom/features/expenses/repositories/expense_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers expense module dependencies.
class ExpenseBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ExpenseRepository>(
      () => ExpenseRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<ExpenseController>(
      () => ExpenseController(Get.find<ExpenseRepository>()),
      fenix: true,
    );
    Get.lazyPut<ExpenseFormController>(
      () => ExpenseFormController(
        Get.find<ExpenseRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
    Get.lazyPut<ExpenseDetailsController>(
      () => ExpenseDetailsController(
        Get.find<ExpenseRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
  }
}
