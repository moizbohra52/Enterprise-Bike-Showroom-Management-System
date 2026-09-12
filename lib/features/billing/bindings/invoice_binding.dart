import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/billing/controllers/invoice_controller.dart';
import 'package:enterprise_bike_showroom/features/billing/repositories/invoice_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers billing (invoice) module dependencies.
class InvoiceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<InvoiceRepository>(
      () => InvoiceRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<InvoiceController>(
      () => InvoiceController(Get.find<InvoiceRepository>()),
      fenix: true,
    );
    Get.lazyPut<InvoiceDetailsController>(
      () => InvoiceDetailsController(Get.find<InvoiceRepository>()),
      fenix: true,
    );
  }
}
