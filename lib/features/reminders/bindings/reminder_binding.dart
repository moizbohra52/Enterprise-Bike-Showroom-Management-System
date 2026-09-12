import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/reminders/controllers/reminder_controller.dart';
import 'package:enterprise_bike_showroom/features/reminders/repositories/reminder_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers reminder module dependencies.
class ReminderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ReminderRepository>(
      () => ReminderRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<ReminderController>(
      () => ReminderController(Get.find<ReminderRepository>()),
      fenix: true,
    );
    Get.lazyPut<ReminderFormController>(
      () => ReminderFormController(
        Get.find<ReminderRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
  }
}
