import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';

/// A payment against an invoice (sale, EMI, service, etc.).
class PaymentModel extends BaseModel {
  PaymentModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.customerId,
    this.customer,
    this.invoiceId,
    this.saleId,
    this.loanId,
    required this.paymentNumber,
    this.paymentDate,
    required this.amount,
    required this.paymentMode,
    this.referenceNumber,
    this.isDownPayment = false,
    this.isEmi = false,
    this.emiInstallmentNo,
    this.status = 'completed',
    this.receivedBy,
    this.notes,
    this.refunded = false,
    this.refundReason,
    this.refundedAt,
  });

  final String? showroomId;
  final String? customerId;
  final dynamic customer;
  final String? invoiceId;
  final String? saleId;
  final String? loanId;
  final String paymentNumber;
  final DateTime? paymentDate;
  final num amount;
  final String paymentMode;
  final String? referenceNumber;
  final bool isDownPayment;
  final bool isEmi;
  final int? emiInstallmentNo;
  final String status;
  final String? receivedBy;
  final String? notes;
  final bool refunded;
  final String? refundReason;
  final DateTime? refundedAt;

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return PaymentModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      invoiceId: SafeJson.asId(json['invoice_id']),
      saleId: SafeJson.asId(json['sale_id']),
      loanId: SafeJson.asId(json['loan_id']),
      paymentNumber: SafeJson.asText(json['payment_number']),
      paymentDate: SafeJson.asDay(json['payment_date']),
      amount: SafeJson.asMoney(json['amount']),
      paymentMode: SafeJson.asText(json['payment_mode'], fallback: 'cash'),
      referenceNumber: SafeJson.asText(json['reference_number']),
      isDownPayment: SafeJson.asBoolOr(json['is_down_payment'], false),
      isEmi: SafeJson.asBoolOr(json['is_emi'], false),
      emiInstallmentNo: SafeJson.asInt(json['emi_installment_no']),
      status: SafeJson.asText(json['status'], fallback: 'completed'),
      receivedBy: SafeJson.asText(json['received_by']),
      notes: SafeJson.asText(json['notes']),
      refunded: SafeJson.asBoolOr(json['is_refunded'], false),
      refundReason: SafeJson.asText(json['refund_reason']),
      refundedAt: SafeJson.asDate(json['refunded_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_id': customerId,
        'invoice_id': invoiceId,
        'sale_id': saleId,
        'loan_id': loanId,
        'payment_number': paymentNumber,
        if (paymentDate != null)
          'payment_date': paymentDate!.toIso8601String(),
        'amount': amount,
        'payment_mode': paymentMode,
        'reference_number': referenceNumber,
        'is_down_payment': isDownPayment,
        'is_emi': isEmi,
        'emi_installment_no': emiInstallmentNo,
        'status': status,
        'received_by': receivedBy,
        'notes': notes,
      };

  String get customerName {
    final dynamic c = customer;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '-');
    return c?.toString() ?? '-';
  }
}
