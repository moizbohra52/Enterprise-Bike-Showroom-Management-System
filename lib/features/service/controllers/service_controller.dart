import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/service/models/service_models.dart';
import 'package:enterprise_bike_showroom/features/service/repositories/service_repository.dart';

/// Service register (workshop board).
class ServiceController extends BaseListController<ServiceRecordModel> {
  ServiceController(ServiceRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    super.onInit();
    refresh();
  }
}

/// New service (job card) form.
class ServiceFormController extends GetxController {
  ServiceFormController(this.repository, this.session);

  final ServiceRepository repository;
  final SessionController session;

  final RxList<Map<String, dynamic>> customers = <Map<String, dynamic>>[].obs;
  final Rx<String?> customerId = Rx<String?>(null);

  final RxList<Map<String, dynamic>> vehicles = <Map<String, dynamic>>[].obs;
  final Rx<String?> vehicleId = Rx<String?>(null);

  final Rx<String> jobType = 'paid'.obs;
  final Rx<num> odometerIn = 0.obs;
  final Rx<String> problem = ''.obs;

  final RxList<ServiceItemModel> items = <ServiceItemModel>[].obs;

  final Rx<num> total = 0.obs;
  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  Future<void> init({String? vehicleId}) async {
    await loadCustomers();
    if (vehicleId != null && vehicleId.isNotEmpty) {
      await _selectVehicleFromId(vehicleId);
    }
  }

  Future<void> loadCustomers() async {
    try {
      customers.assignAll(await repository.activeCustomers());
    } on AppException {
      // Picker stays empty; submit validation will surface the issue.
    }
  }

  Future<void> selectCustomer(String id) async {
    customerId.value = id;
    vehicleId.value = null;
    vehicles.assignAll(await repository.customerVehicles(id));
  }

  Future<void> _selectVehicleFromId(String id) async {
    final Map<String, dynamic>? row = await repository.vehicleById(id);
    if (row == null) return;
    final String? cid = row['customer_id']?.toString();
    if (cid == null) return;
    customers.assignAll(<Map<String, dynamic>>[
      <String, dynamic>{'id': cid, 'name': 'Vehicle owner', 'phone': ''},
    ]);
    customerId.value = cid;
    vehicles.assignAll(<Map<String, dynamic>>[row]);
    vehicleId.value = id;
    odometerIn.value = (row['current_odometer'] as num?)?.toDouble() ?? 0;
  }

  void selectVehicle(String id) {
    vehicleId.value = id;
    for (final Map<String, dynamic> v in vehicles.value) {
      if (v['id']?.toString() == id) {
        odometerIn.value = (v['current_odometer'] as num?)?.toDouble() ?? 0;
        break;
      }
    }
  }

  void addItem({
    required String itemType,
    required String name,
    String partNumber = '',
    num qty = 1,
    num unitPrice = 0,
  }) {
    items.add(ServiceItemModel(
      itemType: itemType,
      name: name,
      partNumber: partNumber,
      qty: qty,
      unitPrice: unitPrice,
      totalAmount: qty * unitPrice,
    ));
    _recalc();
  }

  void updateItem(int index, {num? qty, num? unitPrice}) {
    if (index < 0 || index >= items.value.length) return;
    final ServiceItemModel old = items.value[index];
    final num q = qty ?? old.qty;
    final num p = unitPrice ?? old.unitPrice;
    items.value[index] = ServiceItemModel(
      id: old.id,
      itemType: old.itemType,
      name: old.name,
      partNumber: old.partNumber,
      qty: q,
      unitPrice: p,
      discount: old.discount,
      totalAmount: q * p,
    );
    items.refresh();
    _recalc();
  }

  void removeItem(int index) {
    if (index >= 0 && index < items.value.length) {
      items.removeAt(index);
      _recalc();
    }
  }

  void _recalc() {
    total.value = items.value.fold<num>(
        0, (num sum, ServiceItemModel i) => sum + i.totalAmount);
  }

  Future<bool> submit() async {
    error.value = '';
    if (customerId.value == null || vehicleId.value == null) {
      error.value = 'Select a customer and a vehicle.';
      return false;
    }
    if (session.activeShowroomId.isEmpty) {
      error.value = 'Select an active showroom first.';
      return false;
    }
    saving.value = true;
    try {
      await repository.create(
        vehicleId: vehicleId.value!,
        customerId: customerId.value!,
        showroomId: session.activeShowroomId,
        items: items.value,
        jobType: jobType.value,
        odometerIn: odometerIn.value > 0 ? odometerIn.value : null,
        problemDescription:
            problem.value.trim().isEmpty ? null : problem.value.trim(),
      );
      return true;
    } on AppException catch (e) {
      error.value = e.message;
      return false;
    } finally {
      saving.value = false;
    }
  }
}

/// Service details: items + complete action.
class ServiceDetailsController extends GetxController {
  ServiceDetailsController(this.repository);

  final ServiceRepository repository;

  final Rx<ServiceRecordModel?> service = Rx<ServiceRecordModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool busy = false.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      service.value = await repository.getById(id);
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> complete({
    required num odometerOut,
    required String workDone,
    String paymentMode = 'cash',
  }) async {
    final ServiceRecordModel? current = service.value;
    if (current?.id == null) return false;
    busy.value = true;
    try {
      await repository.complete(
        serviceId: current!.id!,
        odometerOut: odometerOut,
        workDone: workDone,
        paymentMode: paymentMode,
      );
      await load(current.id!);
      return true;
    } on AppException {
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> changeStatus(String status) async {
    final ServiceRecordModel? current = service.value;
    if (current?.id == null) return false;
    try {
      await repository.updateStatus(current!.id!, status);
      await load(current.id!);
      return true;
    } on AppException {
      return false;
    }
  }
}
