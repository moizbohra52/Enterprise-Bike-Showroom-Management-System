import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A customer loan (created inside `create_sale_transaction` for EMI sales).
class LoanModel extends BaseModel {
  LoanModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.customerId,
    this.customer,
    this.saleId,
    required this.loanNumber,
    this.planId,
    this.loanAmount = 0,
    this.downPayment = 0,
    this.interestRate = 0,
    this.method = 'reducing',
    this.tenureMonths = 0,
    this.monthlyEmi = 0,
    this.totalEmi = 0,
    this.totalInterest = 0,
    this.outstandingAmount = 0,
    this.startDate,
    this.endDate,
    this.status = 'active',
    this.closedAt,
  });

  final String? showroomId;
  final String? customerId;
  final dynamic customer;
  final String? saleId;

  final String loanNumber;
  final String? planId;
  final num loanAmount;
  final num downPayment;
  final num interestRate;
  final String method; // reducing | flat
  final int tenureMonths;
  final num monthlyEmi;
  final num totalEmi;
  final num totalInterest;
  final num outstandingAmount;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status; // active | closed | defaulted | cancelled
  final DateTime? closedAt;

  factory LoanModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return LoanModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      saleId: SafeJson.asId(json['sale_id']),
      loanNumber: SafeJson.asText(json['loan_number']),
      planId: SafeJson.asId(json['plan_id']),
      loanAmount: SafeJson.asMoney(json['loan_amount']),
      downPayment: SafeJson.asMoney(json['down_payment']),
      interestRate: SafeJson.asMoney(json['interest_rate']),
      method: SafeJson.asText(json['method'], fallback: 'reducing'),
      tenureMonths: SafeJson.asIntOr(json['tenure_months'], 0),
      monthlyEmi: SafeJson.asMoney(json['monthly_emi']),
      totalEmi: SafeJson.asMoney(json['total_emi']),
      totalInterest: SafeJson.asMoney(json['total_interest']),
      outstandingAmount: SafeJson.asMoney(json['outstanding_amount']),
      startDate: SafeJson.asDay(json['start_date']),
      endDate: SafeJson.asDay(json['end_date']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      closedAt: SafeJson.asDate(json['closed_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_id': customerId,
        'sale_id': saleId,
        'loan_number': loanNumber,
        'plan_id': planId,
        'loan_amount': loanAmount,
        'down_payment': downPayment,
        'interest_rate': interestRate,
        'method': method,
        'tenure_months': tenureMonths,
        'monthly_emi': monthlyEmi,
        'total_emi': totalEmi,
        'total_interest': totalInterest,
        'outstanding_amount': outstandingAmount,
        if (startDate != null)
          'start_date': startDate!.toIso8601String(),
        if (endDate != null) 'end_date': endDate!.toIso8601String(),
        'status': status,
      };

  String get customerName {
    final dynamic c = customer;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '-');
    return c?.toString() ?? '-';
  }
}

/// One row of the EMI schedule.
class EmiScheduleModel {
  EmiScheduleModel({
    this.id,
    this.loanId,
    required this.installmentNo,
    required this.dueDate,
    required this.emiAmount,
    this.principalPart = 0,
    this.interestPart = 0,
    this.balanceAfter = 0,
    this.status = 'upcoming',
    this.paidAmount = 0,
    this.paidAt,
  });

  final String? id;
  final String? loanId;
  final int installmentNo;
  final DateTime dueDate;
  final num emiAmount;
  final num principalPart;
  final num interestPart;
  final num balanceAfter;
  final String status; // upcoming | due | partial | paid | overdue | cancelled
  final num paidAmount;
  final DateTime? paidAt;

  factory EmiScheduleModel.fromJson(Map<String, dynamic> json) {
    return EmiScheduleModel(
      id: SafeJson.asId(json['id']),
      loanId: SafeJson.asId(json['loan_id']),
      installmentNo: SafeJson.asIntOr(json['installment_no'], 0),
      dueDate: SafeJson.asDay(json['due_date']) ?? DateTime.now(),
      emiAmount: SafeJson.asMoney(json['emi_amount']),
      principalPart: SafeJson.asMoney(json['principal_amount']),
      interestPart: SafeJson.asMoney(json['interest_amount']),
      balanceAfter: SafeJson.asMoney(json['balance_after']),
      status: SafeJson.asText(json['status'], fallback: 'upcoming'),
      paidAmount: SafeJson.asMoney(json['paid_amount']),
      paidAt: SafeJson.asDate(json['paid_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'loan_id': loanId,
        'installment_no': installmentNo,
        'due_date': dueDate.toIso8601String(),
        'emi_amount': emiAmount,
        'principal_amount': principalPart,
        'interest_amount': interestPart,
        'balance_after': balanceAfter,
        'status': status,
        'paid_amount': paidAmount,
        if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
      };
}
