import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A granted free-service entitlement for a vehicle.
class FreeServiceGrantModel extends BaseModel {
  FreeServiceGrantModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.vehicleId,
    this.vehicle,
    this.planId,
    this.planName = '',
    required this.grantNumber,
    this.startDate,
    this.endDate,
    this.mileageLimit = 0,
    this.usedMileage = 0,
    this.status = 'active',
    this.usedServiceId,
  });

  final String? showroomId;
  final String? vehicleId;
  final dynamic vehicle;
  final String? planId;
  final String planName;
  final String grantNumber;
  final DateTime? startDate;
  final DateTime? endDate;
  final num mileageLimit;
  final num usedMileage;
  final String status; // active | used | expired
  final String? usedServiceId;

  factory FreeServiceGrantModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return FreeServiceGrantModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      vehicleId: SafeJson.asId(json['vehicle_id']),
      vehicle: json['vehicle'],
      planId: SafeJson.asId(json['plan_id']),
      planName: SafeJson.asText(json['plan_name']),
      grantNumber: SafeJson.asText(json['grant_number']),
      startDate: SafeJson.asDay(json['start_date']),
      endDate: SafeJson.asDay(json['end_date']),
      mileageLimit: SafeJson.asMoney(json['mileage_limit']),
      usedMileage: SafeJson.asMoney(json['used_mileage']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      usedServiceId: SafeJson.asId(json['used_service_id']),
    );
  }

  String get vehicleLabel {
    final dynamic v = vehicle;
    if (v is Map) {
      final Map<String, dynamic> vm = SafeJson.asMap(v);
      return SafeJson.asText(vm['registration_number']);
    }
    return v?.toString() ?? '-';
  }

  num get remainingMileage =>
      (mileageLimit - usedMileage) < 0 ? 0 : mileageLimit - usedMileage;
}
