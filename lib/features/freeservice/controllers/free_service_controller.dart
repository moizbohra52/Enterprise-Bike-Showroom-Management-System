import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/features/freeservice/models/free_service_models.dart';
import 'package:enterprise_bike_showroom/features/freeservice/repositories/free_service_repository.dart';
import 'package:enterprise_bike_showroom/features/service/models/service_models.dart';

/// Free-service grants register.
class FreeServiceController extends BaseListController<FreeServiceGrantModel> {
  FreeServiceController(this.repository)
      : super(repository.listGrants, pageSize: 20);

  final FreeServiceRepository repository;

  final RxList<FreeServicePlanModel> plans = <FreeServicePlanModel>[].obs;

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
    loadPlans();
  }

  Future<void> loadPlans() async {
    try {
      plans.assignAll(await repository.plans());
    } catch (_) {
      // Plans panel stays empty on failure.
    }
  }
}
