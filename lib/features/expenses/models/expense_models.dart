import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// An expense category (seeded; user-extensible per showroom).
class ExpenseCategoryModel extends BaseModel {
  ExpenseCategoryModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    required this.name,
    this.icon = 'category',
    this.requiresApproval = true,
    this.isSystem = false,
    this.status = 'active',
  });

  final String? showroomId;
  final String name;
  final String icon;
  final bool requiresApproval;
  final bool isSystem;
  final String status;

  factory ExpenseCategoryModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return ExpenseCategoryModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      name: SafeJson.asText(json['name']),
      icon: SafeJson.asText(json['icon'], fallback: 'category'),
      requiresApproval:
          SafeJson.asBoolOr(json['requires_approval'], true),
      isSystem: SafeJson.asBoolOr(json['is_system'], false),
      status: SafeJson.asText(json['status'], fallback: 'active'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'name': name,
        'icon': icon,
        'requires_approval': requiresApproval,
        'is_system': isSystem,
        'status': status,
      };
}

/// An expense (office, rent, salary, marketing, …).
class ExpenseModel extends BaseModel {
  ExpenseModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.categoryId,
    this.category,
    this.expenseNumber = '',
    this.date,
    this.description = '',
    this.amount = 0,
    this.paymentMode = 'cash',
    this.referenceNumber = '',
    this.voucherNumber = '',
    this.status = 'pending',
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectionReason,
    this.attachmentPath,
    this.notes = '',
  });

  final String? showroomId;
  final String? categoryId;
  final dynamic category;
  final String expenseNumber;
  final DateTime? date;
  final String description;
  final num amount;
  final String paymentMode;
  final String referenceNumber;
  final String voucherNumber;
  // pending | approved | rejected | paid
  final String status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final String? rejectionReason;
  final String? attachmentPath;
  final String notes;

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return ExpenseModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      categoryId: SafeJson.asId(json['category_id']),
      category: json['category'],
      expenseNumber: SafeJson.asText(json['expense_number']),
      date: SafeJson.asDay(json['date']),
      description: SafeJson.asText(json['description']),
      amount: SafeJson.asMoney(json['amount']),
      paymentMode: SafeJson.asText(json['payment_mode'], fallback: 'cash'),
      referenceNumber: SafeJson.asText(json['reference_number']),
      voucherNumber: SafeJson.asText(json['voucher_number']),
      status: SafeJson.asText(json['status'], fallback: 'pending'),
      approvedBy: SafeJson.asText(json['approved_by']),
      approvedAt: SafeJson.asDate(json['approved_at']),
      rejectedBy: SafeJson.asText(json['rejected_by']),
      rejectionReason: SafeJson.asText(json['rejection_reason']),
      attachmentPath: SafeJson.asText(json['attachment_path']),
      notes: SafeJson.asText(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'category_id': categoryId,
        'expense_number': expenseNumber,
        if (date != null) 'date': date!.toIso8601String(),
        'description': description,
        'amount': amount,
        'payment_mode': paymentMode,
        'reference_number': referenceNumber,
        'voucher_number': voucherNumber,
        'status': status,
        'attachment_path': attachmentPath,
        'notes': notes,
      };

  String get categoryLabel {
    final dynamic c = category;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '-');
    return c?.toString() ?? '-';
  }
}
