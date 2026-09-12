import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// An insurance policy for a vehicle.
class InsurancePolicyModel extends BaseModel {
  InsurancePolicyModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.vehicleId,
    this.vehicle,
    this.customerId,
    this.customer,
    this.insurer = '',
    this.policyNumber = '',
    this.policyType = 'comprehensive',
    this.startDate,
    this.endDate,
    this.premium = 0,
    this.coverageAmount = 0,
    this.status = 'active',
    this.renewalReminderSent = false,
    this.documentPath,
  });

  final String? showroomId;
  final String? vehicleId;
  final dynamic vehicle;
  final String? customerId;
  final dynamic customer;
  final String insurer;
  final String policyNumber;
  // comprehensive | third_party | personal_accident
  final String policyType;
  final DateTime? startDate;
  final DateTime? endDate;
  final num premium;
  final num coverageAmount;
  // active | expired | cancelled
  final String status;
  final bool renewalReminderSent;
  final String? documentPath;

  factory InsurancePolicyModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return InsurancePolicyModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      vehicleId: SafeJson.asId(json['vehicle_id']),
      vehicle: json['vehicle'],
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      insurer: SafeJson.asText(json['insurer']),
      policyNumber: SafeJson.asText(json['policy_number']),
      policyType: SafeJson.asText(json['policy_type'],
          fallback: 'comprehensive'),
      startDate: SafeJson.asDay(json['start_date']),
      endDate: SafeJson.asDay(json['end_date']),
      premium: SafeJson.asMoney(json['premium']),
      coverageAmount: SafeJson.asMoney(json['coverage_amount']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      renewalReminderSent:
          SafeJson.asBoolOr(json['renewal_reminder_sent'], false),
      documentPath: SafeJson.asText(json['document_path']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'vehicle_id': vehicleId,
        'customer_id': customerId,
        'insurer': insurer,
        'policy_number': policyNumber,
        'policy_type': policyType,
        if (startDate != null)
          'start_date': startDate!.toIso8601String(),
        if (endDate != null) 'end_date': endDate!.toIso8601String(),
        'premium': premium,
        'coverage_amount': coverageAmount,
        'status': status,
        'document_path': documentPath,
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

  bool get expiringSoon {
    final DateTime? end = endDate;
    if (end == null) return false;
    final DateTime limit =
        DateTime.now().add(const Duration(days: 45));
    return end.isAfter(DateTime.now()) && end.isBefore(limit);
  }
}
