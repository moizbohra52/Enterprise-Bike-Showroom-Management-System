import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/insurance/models/insurance_models.dart';
import 'package:enterprise_bike_showroom/features/insurance/repositories/insurance_repository.dart';

/// Insurance register.
class InsuranceController extends BaseListController<InsurancePolicyModel> {
  InsuranceController(InsuranceRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }
}

/// Insurance form (add / renew).
class InsuranceFormController extends GetxController {
  InsuranceFormController(this.repository, this.session);

  final InsuranceRepository repository;
  final SessionController session;

  final RxList<Map<String, dynamic>> customers = <Map<String, dynamic>>[].obs;
  final Rx<String?> customerId = Rx<String?>(null);
  final RxList<Map<String, dynamic>> vehicles = <Map<String, dynamic>>[].obs;
  final Rx<String?> vehicleId = Rx<String?>(null);

  final Rx<String> insurer = ''.obs;
  final Rx<String> policyNumber = ''.obs;
  final Rx<String> policyType = 'comprehensive'.obs;
  final Rx<DateTime?> startDate = Rx<DateTime?>(null);
  final Rx<DateTime?> endDate = Rx<DateTime?>(null);
  final Rx<num> premium = 0.obs;
  final Rx<num> coverage = 0.obs;

  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  Future<void> init() async {
    try {
      customers.assignAll(await repository.activeCustomers());
    } catch (AppException) {
      // Picker stays empty; submit validation surfaces the problem.
    }
  }

  Future<void> selectCustomer(String id) async {
    customerId.value = id;
    vehicleId.value = null;
    try {
      vehicles.assignAll(await repository.customerVehicles(id));
    } catch (AppException) {
      vehicles.clear();
    }
  }

  Future<bool> submit() async {
    error.value = '';
    final String? customer = customerId.value;
    final String? vehicle = vehicleId.value;
    final DateTime? start = startDate.value;
    final DateTime? end = endDate.value;
    if (customer == null || vehicle == null) {
      error.value = 'Select customer and vehicle.';
      return false;
    }
    if (start == null || end == null || !end.isAfter(start)) {
      error.value = 'Valid date range required.';
      return false;
    }
    if (premium.value <= 0) {
      error.value = 'Enter the premium paid.';
      return false;
    }
    if (session.activeShowroomId.isEmpty) {
      error.value = 'Select an active showroom first.';
      return false;
    }
    saving.value = true;
    try {
      await repository.create(<String, dynamic>{
        'showroom_id': session.activeShowroomId,
        'customer_id': customer,
        'vehicle_id': vehicle,
        'insurer': insurer.value.trim(),
        'policy_number': policyNumber.value.trim().toUpperCase(),
        'policy_type': policyType.value,
        'start_date': start.toIso8601String().substring(0, 10),
        'end_date': end.toIso8601String().substring(0, 10),
        'premium': premium.value,
        'coverage_amount': coverage.value,
      });
      return true;
    } on AppException catch (e) {
      error.value = e.message;
      return false;
    } finally {
      saving.value = false;
    }
  }
}

/// Insurance details.
class InsuranceDetailsController extends GetxController {
  InsuranceDetailsController(this.repository);

  final InsuranceRepository repository;

  final Rx<InsurancePolicyModel?> policy = Rx<InsurancePolicyModel?>(null);
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      policy.value = await repository.getById(id);
    } finally {
      isLoading.value = false;
    }
  }
}
