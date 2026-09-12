import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/core/constants/entity_constants.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/id_generator.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/models/customer_models.dart';
import 'package:enterprise_bike_showroom/features/customers/repositories/customer_repository.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/connectivity_service.dart';
import 'package:enterprise_bike_showroom/services/sync_service.dart';

/// Customer list controller (with offline-aware create path).
class CustomerController extends BaseListController<CustomerModel> {
  CustomerController(
    CustomerRepository repository,
    SessionController session,
    ConnectivityService connectivity,
    SyncService sync,
  ) : super(repository.list, pageSize: 20) {
    this.repository = repository;
    this.session = session;
    this.connectivity = connectivity;
    this.sync = sync;
  }

  late final CustomerRepository repository;
  late final SessionController session;
  late final ConnectivityService connectivity;
  late final SyncService sync;

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }

  Future<void> openForm({String? id}) async {
    await Get.toNamed(
      AppRoutes.customerForm,
      parameters: <String, String?>{
        if (id != null) 'id': id,
      },
    );
    refresh();
  }

  Future<void> openDetails(CustomerModel customer) async {
    await Get.toNamed(AppRoutes.customerDetails,
        parameters: <String, String?>{'id': customer.id});
  }

  /// Creates a customer — remote when online, queued when offline.
  Future<bool> saveCustomer(Map<String, dynamic> payload, {String? id}) async {
    final Map<String, dynamic> full = <String, dynamic>{
      ...payload,
      if (session.activeShowroomId.isNotEmpty)
        'showroom_id': session.activeShowroomId,
    };
    try {
      if (connectivity.isOnline) {
        if (id != null) {
          await repository.update(id, full);
        } else {
          await repository.create(full);
        }
        return true;
      }
      // Offline path: local id + sync queue.
      final String localId = id ?? IdGenerator.uuid();
      if (id == null) {
        full['id'] = localId;
      }
      await sync.enqueue(SyncQueueEntry(
        id: IdGenerator.uuid(),
        entityType: EntityType.customer,
        entityId: localId,
        operation:
            id == null ? SyncOperation.create : SyncOperation.update,
        payload: full,
        createdAt: DateTime.now(),
      ));
      return true;
    } on AppException catch (e) {
      AppLogger.error('CUSTOMERS', 'save failed', error: e);
      rethrow;
    }
  }

  Future<bool> deleteCustomer(CustomerModel customer) async {
    try {
      if (connectivity.isOnline) {
        await repository.softDelete(customer.id!);
        return true;
      }
      await sync.enqueue(SyncQueueEntry(
        id: IdGenerator.uuid(),
        entityType: EntityType.customer,
        entityId: customer.id!,
        operation: SyncOperation.delete,
        payload: <String, dynamic>{},
        createdAt: DateTime.now(),
      ));
      return true;
    } on AppException {
      return false;
    }
  }
}

/// Customer 360: profile + all related data.
class CustomerDetailsController extends GetxController {
  CustomerDetailsController(this.repository);

  final CustomerRepository repository;

  final Rx<CustomerModel?> customer = Rx<CustomerModel?>(null);
  final RxList<CustomerVehicleModel> vehicles = <CustomerVehicleModel>[].obs;
  final RxList<Map<String, dynamic>> sales = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> invoices = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> payments = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> emiRows = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> services = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> warranties = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> insurance = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> reminders = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> documents = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> timeline = <Map<String, dynamic>>[].obs;
  final Rx<num> outstanding = 0.obs;
  final RxBool isLoading = true.obs;

  /// Loads the full customer profile.
  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      final CustomerModel? c = await repository.getById(id);
      if (c == null) return;
      customer.value = c;
      vehicles.assignAll(await repository.vehicles(id));
      sales.assignAll(
          await repository.relatedRows('sales', column: 'customer_id', customerId: id));
      invoices.assignAll(await repository.relatedRows(
          'invoices', column: 'customer_id', customerId: id, order: 'created_at'));
      payments.assignAll(await repository.relatedRows(
          'payments', column: 'customer_id', customerId: id, order: 'created_at'));

      // EMI rows via the customer's loans.
      final List<Map<String, dynamic>> loans = await repository.relatedRows(
          'loans', column: 'customer_id', customerId: id);
      final List<Map<String, dynamic>> emi = <Map<String, dynamic>>[];
      for (final Map<String, dynamic> loan in loans) {
        final String? loanId = SafeText(loan['loan_number']);
        final String? loanIdKey = SafeId(loan['id']);
        if (loanIdKey != null) {
          emi.addAll(await repository.relatedRows(
              'emi_schedules',
              column: 'loan_id',
              customerId: loanIdKey,
              order: 'due_date'));
        }
      }
      emiRows.assignAll(emi);

      // Vehicle-scoped tabs.
      final List<Map<String, dynamic>> serviceRows = <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> warrantyRows = <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> insuranceRows = <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> reminderRows = <Map<String, dynamic>>[];
      for (final CustomerVehicleModel v in vehicles.value) {
        if (v.id == null) continue;
        serviceRows.addAll(await repository.relatedRows(
            'service_records', column: 'vehicle_id', customerId: v.id!, order: 'created_at'));
        warrantyRows.addAll(await repository.relatedRows(
            'warranties', column: 'vehicle_id', customerId: v.id!));
        insuranceRows.addAll(await repository.relatedRows(
            'insurance_policies', column: 'vehicle_id', customerId: v.id!));
        reminderRows.addAll(await repository.relatedRows(
            'reminders', column: 'vehicle_id', customerId: v.id!));
      }
      services.assignAll(serviceRows);
      warranties.assignAll(warrantyRows);
      insurance.assignAll(insuranceRows);
      reminders.assignAll(reminderRows);

      documents.assignAll(await repository.relatedRows(
          'attachments', column: 'entity_id', customerId: id));
      timeline.assignAll(await repository.timeline(id));
      outstanding.value = await repository.outstanding(id);
    } finally {
      isLoading.value = false;
    }
  }

  /// Deletes the customer (soft) and returns to the list.
  Future<bool> delete() async {
    final CustomerModel? current = customer.value;
    if (current?.id == null) return false;
    try {
      await repository.softDelete(current!.id!);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Small helpers to read wire rows without full models.
String? SafeText(dynamic value) {
  if (value == null) return null;
  final String s = value.toString();
  return s.isEmpty ? null : s;
}

String? SafeId(dynamic value) {
  if (value == null) return null;
  final String s = value.toString();
  return s.isEmpty ? null : s;
}
