import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/customers/models/customer_models.dart';
import 'package:enterprise_bike_showroom/features/customers/repositories/customer_repository.dart';

/// Vehicle 360: a single customer vehicle and its lifetime data.
class VehicleDetailsController extends GetxController {
  VehicleDetailsController(this.repository);

  final CustomerRepository repository;

  final Rx<CustomerVehicleModel?> vehicle = Rx<CustomerVehicleModel?>(null);
  final RxList<Map<String, dynamic>> services = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> warranties = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> insurance = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> reminders = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      vehicle.value = await repository.vehicleById(id);
      final String? vehicleId = id;
      services.assignAll(await repository.relatedRows(
          'service_records', column: 'vehicle_id', customerId: vehicleId!, order: 'created_at'));
      warranties.assignAll(await repository.relatedRows(
          'warranties', column: 'vehicle_id', customerId: vehicleId));
      insurance.assignAll(await repository.relatedRows(
          'insurance_policies', column: 'vehicle_id', customerId: vehicleId));
      reminders.assignAll(await repository.relatedRows(
          'reminders', column: 'vehicle_id', customerId: vehicleId));
    } finally {
      isLoading.value = false;
    }
  }

  /// Updates odometer (from a completed service) or warranty expiry.
  Future<void> updateOdometer(num km) async {
    final CustomerVehicleModel? current = vehicle.value;
    if (current?.id == null) return;
    await repository.updateVehicle(current!.id!, <String, dynamic>{
      'current_odometer': km,
    });
    vehicle.value = vehicle.value?.copyWithOdometer(km);
  }

  bool get warrantyActive {
    final CustomerVehicleModel? v = vehicle.value;
    final DateTime? end = v?.warrantyEnd;
    return end != null && end.isAfter(DateTime.now());
  }

  String get warrantySummary {
    final CustomerVehicleModel? v = vehicle.value;
    if (v == null) return '-';
    if (v.warrantyEnd == null) return 'No warranty';
    return '${AppFormatters.date(v.warrantyStart)} → ${AppFormatters.date(v.warrantyEnd)}';
  }
}

extension VehicleModelCopy on CustomerVehicleModel {
  CustomerVehicleModel copyWithOdometer(num km) => CustomerVehicleModel(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        customerId: customerId,
        inventoryId: inventoryId,
        productId: productId,
        product: product,
        registrationNumber: registrationNumber,
        registrationDate: registrationDate,
        chassisNumber: chassisNumber,
        engineNumber: engineNumber,
        purchaseDate: purchaseDate,
        deliveryDate: deliveryDate,
        currentOdometer: km,
        warrantyStart: warrantyStart,
        warrantyEnd: warrantyEnd,
        insuranceStart: insuranceStart,
        insuranceEnd: insuranceEnd,
        nextServiceDate: nextServiceDate,
        nextServiceKm: nextServiceKm,
        status: status,
      );
}
