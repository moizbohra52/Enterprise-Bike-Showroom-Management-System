import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A reminder (EMI due, service due, insurance renewal, custom).
class ReminderModel extends BaseModel {
  ReminderModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.customerId,
    this.customer,
    this.vehicleId,
    this.loanId,
    required this.title,
    this.message = '',
    this.reminderDate,
    this.type = 'custom',
    this.referenceType,
    this.referenceId,
    this.status = 'pending', // pending | done | dismissed
    this.completedAt,
    this.pushSent = false,
  });

  final String? showroomId;
  final String? customerId;
  final dynamic customer;
  final String? vehicleId;
  final String? loanId;
  final String title;
  final String message;
  final DateTime? reminderDate;

  /// emi_due | service_due | insurance_renewal | warranty_expiry | custom
  final String type;
  final String? referenceType;
  final String? referenceId;
  final String status;
  final DateTime? completedAt;
  final bool pushSent;

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return ReminderModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      vehicleId: SafeJson.asId(json['vehicle_id']),
      loanId: SafeJson.asId(json['loan_id']),
      title: SafeJson.asText(json['title']),
      message: SafeJson.asText(json['message']),
      reminderDate: SafeJson.asDay(json['reminder_date']),
      type: SafeJson.asText(json['type'], fallback: 'custom'),
      referenceType: SafeJson.asText(json['reference_type']),
      referenceId: SafeJson.asId(json['reference_id']),
      status: SafeJson.asText(json['status'], fallback: 'pending'),
      completedAt: SafeJson.asDate(json['completed_at']),
      pushSent: SafeJson.asBoolOr(json['push_sent'], false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_id': customerId,
        'vehicle_id': vehicleId,
        'loan_id': loanId,
        'title': title,
        'message': message,
        if (reminderDate != null)
          'reminder_date': reminderDate!.toIso8601String(),
        'type': type,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'status': status,
      };

  String get customerName {
    final dynamic c = customer;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '');
    return c?.toString() ?? '';
  }
}
