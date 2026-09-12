import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/accounting/controllers/accounting_controller.dart';
import 'package:enterprise_bike_showroom/features/accounting/repositories/accounting_repository.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers accounting module dependencies.
class AccountingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AccountingRepository>(
      () => AccountingRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<AccountController>(
      () => AccountController(Get.find<AccountingRepository>()),
      fenix: true,
    );
    Get.lazyPut<JournalController>(
      () => JournalController(Get.find<AccountingRepository>()),
      fenix: true,
    );
    Get.lazyPut<JournalDetailsController>(
      () => JournalDetailsController(Get.find<AccountingRepository>()),
      fenix: true,
    );
    Get.lazyPut<ManualEntryController>(
      () => ManualEntryController(
        Get.find<AccountingRepository>(),
        Get.find<SessionController>(),
      ),
      fenix: true,
    );
  }
}
