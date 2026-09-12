import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/controllers/customer_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/controllers/vehicle_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/repositories/customer_repository.dart';
import 'package:enterprise_bike_showroom/services/connectivity_service.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';
import 'package:enterprise_bike_showroom/services/sync_service.dart';

// LocalDatabaseService is injected (Get.find) as the second argument of
// CustomerRepository (registered as a global singleton in main.dart).

/// Registers customer module dependencies.
class CustomerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CustomerRepository>(
      () => CustomerRepository(Get.find<SupabaseService>(), Get.find()),
      fenix: true,
    );
    Get.lazyPut<CustomerController>(
      () => CustomerController(
        Get.find<CustomerRepository>(),
        Get.find<SessionController>(),
        Get.find<ConnectivityService>(),
        Get.find<SyncService>(),
      ),
      fenix: true,
    );
    Get.lazyPut<CustomerDetailsController>(
      () => CustomerDetailsController(Get.find<CustomerRepository>()),
      fenix: true,
    );
    Get.lazyPut<VehicleDetailsController>(
      () => VehicleDetailsController(Get.find<CustomerRepository>()),
      fenix: true,
    );
  }
}
