import 'package:enterprise_bike_showroom/features/dashboard/controllers/dashboard_controller.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';
import 'package:get/get.dart';

/// Registers the dashboard controller (services are global).
class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DashboardController>(
      () => DashboardController(
        Get.find<SupabaseService>(),
        Get.find(),
        Get.find(),
      ),
      fenix: true,
    );
  }
}
