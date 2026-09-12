import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/reports/models/report_definition.dart';
import 'package:enterprise_bike_showroom/features/reports/repositories/report_repository.dart';

/// Report catalog screen.
class ReportCatalogController extends GetxController {
  final List<ReportDefinition> reports = ReportCatalog.all;
}

/// One report: rows + export.
class ReportViewController extends GetxController {
  ReportViewController(this.repository);

  final ReportRepository repository;

  final Rx<ReportDefinition?> definition = Rx<ReportDefinition?>(null);
  final RxList<Map<String, dynamic>> rows = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool exporting = false.obs;
  final Rx<String> error = ''.obs;

  /// Loads a report by catalog key.
  Future<void> load(String key) async {
    definition.value = ReportCatalog.byKey(key);
    await refresh();
  }

  Future<void> refresh() async {
    final ReportDefinition? d = definition.value;
    if (d == null) return;
    isLoading.value = true;
    error.value = '';
    try {
      rows.assignAll(await repository.run(d));
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }
}
