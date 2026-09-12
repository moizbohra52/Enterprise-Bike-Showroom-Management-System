import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/reports/controllers/report_controller.dart';
import 'package:enterprise_bike_showroom/features/reports/repositories/report_repository.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Registers reporting module dependencies.
class ReportBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ReportRepository>(
      () => ReportRepository(Get.find<SupabaseService>()),
      fenix: true,
    );
    Get.lazyPut<ReportCatalogController>(() => ReportCatalogController(),
        fenix: true);
    Get.lazyPut<ReportViewController>(
      () => ReportViewController(Get.find<ReportRepository>()),
      fenix: true,
    );
  }
}
