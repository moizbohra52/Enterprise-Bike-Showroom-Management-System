import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A billing line on an invoice.
class InvoiceLineItemModel {
  InvoiceLineItemModel({
    this.id,
    required this.itemType,
    this.lineNumber = 1,
    required this.description,
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
    this.taxRate = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
  });

  final String? id;
  final String itemType; // vehicle | accessory | addon | service
  final int lineNumber;
  final String description;
  final num qty;
  final num unitPrice;
  final num discount;
  final num taxRate;
  final num taxAmount;
  final num totalAmount;

  factory InvoiceLineItemModel.fromJson(Map<String, dynamic> json) {
    return InvoiceLineItemModel(
      id: SafeJson.asId(json['id']),
      itemType: SafeJson.asText(json['item_type'], fallback: 'vehicle'),
      lineNumber: SafeJson.asIntOr(json['line_number'], 1),
      description: SafeJson.asText(json['description']),
      qty: SafeJson.asMoney(json['qty']),
      unitPrice: SafeJson.asMoney(json['unit_price']),
      discount: SafeJson.asMoney(json['discount_amount']),
      taxRate: SafeJson.asMoney(json['tax_rate']),
      taxAmount: SafeJson.asMoney(json['tax_amount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'item_type': itemType,
        'line_number': lineNumber,
        'description': description,
        'qty': qty,
        'unit_price': unitPrice,
        'discount_amount': discount,
        'tax_rate': taxRate,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
      };
}

/// An invoice (billing document against a sale).
class InvoiceModel extends BaseModel {
  InvoiceModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.customerId,
    this.customer,
    this.saleId,
    required this.invoiceNumber,
    this.invoiceDate,
    this.dueDate,
    this.status = 'unpaid',
    this.paymentMode,
    this.subtotal = 0,
    this.discountAmount = 0,
    this.taxRate = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.outstandingAmount = 0,
    this.lineItems = const <InvoiceLineItemModel>[],
    this.voidReason,
    this.voidedAt,
    this.notes,
  });

  final String? showroomId;
  final String? customerId;
  final dynamic customer;
  final String? saleId;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final String status; // unpaid | partial | paid | overdue | void
  final String? paymentMode;
  final num subtotal;
  final num discountAmount;
  final num taxRate;
  final num taxAmount;
  final num totalAmount;
  final num paidAmount;
  final num outstandingAmount;
  final List<InvoiceLineItemModel> lineItems;
  final String? voidReason;
  final DateTime? voidedAt;
  final String? notes;

  factory InvoiceModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return InvoiceModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      saleId: SafeJson.asId(json['sale_id']),
      invoiceNumber: SafeJson.asText(json['invoice_number']),
      invoiceDate: SafeJson.asDay(json['invoice_date']),
      dueDate: SafeJson.asDay(json['due_date']),
      status: SafeJson.asText(json['status'], fallback: 'unpaid'),
      paymentMode: SafeJson.asText(json['payment_mode']),
      subtotal: SafeJson.asMoney(json['subtotal_amount']),
      discountAmount: SafeJson.asMoney(json['discount_amount']),
      taxRate: SafeJson.asMoney(json['tax_rate']),
      taxAmount: SafeJson.asMoney(json['tax_amount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
      paidAmount: SafeJson.asMoney(json['paid_amount']),
      outstandingAmount: SafeJson.asMoney(json['outstanding_amount']),
      lineItems: <InvoiceLineItemModel>[
        for (final dynamic row in SafeJson.asList(json['invoice_items']))
          InvoiceLineItemModel.fromJson(SafeJson.asMap(row)),
      ],
      voidReason: SafeJson.asText(json['void_reason']),
      voidedAt: SafeJson.asDate(json['voided_at']),
      notes: SafeJson.asText(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_id': customerId,
        'sale_id': saleId,
        'invoice_number': invoiceNumber,
        if (invoiceDate != null)
          'invoice_date': invoiceDate!.toIso8601String(),
        if (dueDate != null) 'due_date': dueDate!.toIso8601String(),
        'status': status,
        'payment_mode': paymentMode,
        'subtotal_amount': subtotal,
        'discount_amount': discountAmount,
        'tax_rate': taxRate,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'paid_amount': paidAmount,
        'outstanding_amount': outstandingAmount,
        'void_reason': voidReason,
        'notes': notes,
      };

  String get customerName {
    final dynamic c = customer;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '-');
    return c?.toString() ?? '-';
  }
}
