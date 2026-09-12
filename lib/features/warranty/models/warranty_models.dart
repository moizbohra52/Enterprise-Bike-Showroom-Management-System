import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A vehicle warranty (created at delivery; claimable within terms).
class WarrantyModel extends BaseModel {
  WarrantyModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.vehicleId,
    this.vehicle,
    this.customerId,
    this.customer,
    this.saleId,
    required this.warrantyNumber,
    required this.type, // engine | gearbox | comprehensive | manufacturer
    this.startDate,
    this.endDate,
    this.mileageLimit = 0,
    this.coverage = '',
    this.exclusions = '',
    this.status = 'active',
    this.claimsCount = 0,
    this.activatedAt,
  });

  final String? showroomId;
  final String? vehicleId;
  final dynamic vehicle;
  final String? customerId;
  final dynamic customer;
  final String? saleId;
  final String warrantyNumber;
  final String type;
  final DateTime? startDate;
  final DateTime? endDate;
  final num mileageLimit;
  final String coverage;
  final String exclusions;
  // active | expired | voided
  final String status;
  final int claimsCount;
  final DateTime? activatedAt;

  factory WarrantyModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return WarrantyModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      vehicleId: SafeJson.asId(json['vehicle_id']),
      vehicle: json['vehicle'],
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      saleId: SafeJson.asId(json['sale_id']),
      warrantyNumber: SafeJson.asText(json['warranty_number']),
      type: SafeJson.asText(json['type'], fallback: 'comprehensive'),
      startDate: SafeJson.asDay(json['start_date']),
      endDate: SafeJson.asDay(json['end_date']),
      mileageLimit: SafeJson.asMoney(json['mileage_limit']),
      coverage: SafeJson.asText(json['coverage']),
      exclusions: SafeJson.asText(json['exclusions']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      claimsCount: SafeJson.asIntOr(json['claims_count'], 0),
      activatedAt: SafeJson.asDate(json['activated_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'vehicle_id': vehicleId,
        'customer_id': customerId,
        'sale_id': saleId,
        'warranty_number': warrantyNumber,
        'type': type,
        if (startDate != null)
          'start_date': startDate!.toIso8601String(),
        if (endDate != null) 'end_date': endDate!.toIso8601String(),
        'mileage_limit': mileageLimit,
        'coverage': coverage,
        'exclusions': exclusions,
        'status': status,
      };

  String get vehicleLabel {
    final dynamic v = vehicle;
    if (v is Map) {
      final Map<String, dynamic> vm = SafeJson.asMap(v);
      return SafeJson.asText(vm['registration_number']);
    }
    return v?.toString() ?? '-';
  }

  String get customerName {
    final dynamic c = customer;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '-');
    return c?.toString() ?? '-';
  }

  bool get inDateRange {
    final DateTime? end = endDate;
    return end == null || end.isAfter(DateTime.now());
  }
}

/// A warranty claim.
class WarrantyClaimModel extends BaseModel {
  WarrantyClaimModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.warrantyId,
    this.serviceId,
    required this.claimNumber,
    this.claimDate,
    this.description = '',
    this.estimatedCost = 0,
    this.status = 'submitted', // submitted | approved | rejected | completed
    this.decisionNotes = '',
  });

  final String? warrantyId;
  final String? serviceId;
  final String claimNumber;
  final DateTime? claimDate;
  final String description;
  final num estimatedCost;
  final String status;
  final String decisionNotes;

  factory WarrantyClaimModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return WarrantyClaimModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      warrantyId: SafeJson.asId(json['warranty_id']),
      serviceId: SafeJson.asId(json['service_id']),
      claimNumber: SafeJson.asText(json['claim_number']),
      claimDate: SafeJson.asDay(json['claim_date']),
      description: SafeJson.asText(json['description']),
      estimatedCost: SafeJson.asMoney(json['estimated_cost']),
      status: SafeJson.asText(json['status'], fallback: 'submitted'),
      decisionNotes: SafeJson.asText(json['decision_notes']),
    );
  }
}
