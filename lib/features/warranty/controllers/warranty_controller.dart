import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/warranty/models/warranty_models.dart';
import 'package:enterprise_bike_showroom/features/warranty/repositories/warranty_repository.dart';

/// Warranty register.
class WarrantyController extends BaseListController<WarrantyModel> {
  WarrantyController(WarrantyRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    super.onInit();
    refresh();
  }
}

/// Warranty details + claims workflow.
class WarrantyDetailsController extends GetxController {
  WarrantyDetailsController(this.repository);

  final WarrantyRepository repository;

  final Rx<WarrantyModel?> warranty = Rx<WarrantyModel?>(null);
  final RxList<WarrantyClaimModel> claims = <WarrantyClaimModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool busy = false.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      warranty.value = await repository.getById(id);
      claims.assignAll(await repository.claims(id));
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> raiseClaim(String description, {num? estimatedCost}) async {
    final WarrantyModel? current = warranty.value;
    if (current?.id == null) return false;
    busy.value = true;
    try {
      final WarrantyClaimModel claim = await repository.raiseClaim(
        warrantyId: current!.id!,
        description: description,
        estimatedCost: estimatedCost,
      );
      claims.insert(0, claim);
      return true;
    } on AppException {
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> decideClaim(
      WarrantyClaimModel claim, String status, String notes) async {
    try {
      final WarrantyClaimModel updated =
          await repository.decideClaim(claim.id!, status, notes);
      final int index = claims.value.indexWhere(
          (WarrantyClaimModel c) => c.id == updated.id);
      if (index >= 0) claims.value[index] = updated;
      claims.refresh();
      return true;
    } on AppException {
      return false;
    }
  }
}
