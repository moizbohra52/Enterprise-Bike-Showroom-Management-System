import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/dashboard/controllers/dashboard_controller.dart';
import 'package:enterprise_bike_showroom/features/dashboard/repositories/dashboard_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers dashboard dependencies (aggregates only - read-only module).
class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DashboardRepository>(
      () => DashboardRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<DashboardController>(
      () => DashboardController(
        repository: Get.find<DashboardRepository>(),
        session: Get.find<SessionController>(),
      ),
      fenix: true,
    );
  }
}
