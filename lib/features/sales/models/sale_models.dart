import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A line on a sale (vehicle, accessory or add-on).
class SaleLineItemModel {
  SaleLineItemModel({
    this.id,
    required this.itemType,
    this.inventoryId,
    this.productId,
    this.lineNumber = 1,
    required this.name,
    this.color,
    this.chassisNumber,
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
    this.totalAmount = 0,
  });

  final String? id;
  final String itemType; // vehicle | accessory | addon
  final String? inventoryId;
  final String? productId;
  final int lineNumber;
  final String name;
  final String? color;
  final String? chassisNumber;
  final num qty;
  final num unitPrice;
  final num discount;
  final num totalAmount;

  factory SaleLineItemModel.fromJson(Map<String, dynamic> json) {
    return SaleLineItemModel(
      id: SafeJson.asId(json['id']),
      itemType: SafeJson.asText(json['item_type'], fallback: 'vehicle'),
      inventoryId: SafeJson.asId(json['inventory_id']),
      productId: SafeJson.asId(json['product_id']),
      lineNumber: SafeJson.asIntOr(json['line_number'], 1),
      name: SafeJson.asText(json['name']),
      color: SafeJson.asText(json['color']),
      chassisNumber: SafeJson.asText(json['chassis_number']),
      qty: SafeJson.asMoney(json['qty']),
      unitPrice: SafeJson.asMoney(json['unit_price']),
      discount: SafeJson.asMoney(json['discount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'item_type': itemType,
        'inventory_id': inventoryId,
        'product_id': productId,
        'line_number': lineNumber,
        'name': name,
        'color': color,
        'chassis_number': chassisNumber,
        'qty': qty,
        'unit_price': unitPrice,
        'discount': discount,
        'total_amount': totalAmount,
      };
}

/// A sale (the central transaction of the business model).
class SaleModel extends BaseModel {
  SaleModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.customerId,
    this.customer,
    required this.saleNumber,
    this.saleDate,
    this.saleType = 'retail',
    this.status = 'completed',
    this.paymentMode = 'cash',
    this.emi = false,
    this.subtotal = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.balanceAmount = 0,
    this.lineItems = const <SaleLineItemModel>[],
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceStatus,
    this.deliveryDate,
    this.warrantyStart,
    this.warrantyEnd,
    this.notes,
  });

  final String? showroomId;
  final String? customerId;
  final dynamic customer;
  final String saleNumber;
  final DateTime? saleDate;
  final String saleType;
  final String status;
  final String paymentMode;
  final bool emi;
  final num subtotal;
  final num discountAmount;
  final num taxAmount;
  final num totalAmount;
  final num paidAmount;
  final num balanceAmount;
  final List<SaleLineItemModel> lineItems;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? invoiceStatus;
  final DateTime? deliveryDate;
  final DateTime? warrantyStart;
  final DateTime? warrantyEnd;
  final String? notes;

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return SaleModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      saleNumber: SafeJson.asText(json['sale_number']),
      saleDate: SafeJson.asDay(json['sale_date']),
      saleType: SafeJson.asText(json['sale_type'], fallback: 'retail'),
      status: SafeJson.asText(json['status'], fallback: 'completed'),
      paymentMode: SafeJson.asText(json['payment_mode'], fallback: 'cash'),
      emi: SafeJson.asBoolOr(json['is_emi'], false),
      subtotal: SafeJson.asMoney(json['subtotal_amount']),
      discountAmount: SafeJson.asMoney(json['discount_amount']),
      taxAmount: SafeJson.asMoney(json['tax_amount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
      paidAmount: SafeJson.asMoney(json['paid_amount']),
      balanceAmount: SafeJson.asMoney(json['balance_amount']),
      lineItems: <SaleLineItemModel>[
        for (final dynamic row in SafeJson.asList(json['sale_items']))
          SaleLineItemModel.fromJson(SafeJson.asMap(row)),
      ],
      invoiceId: _firstInvoiceId(json['invoices']),
      invoiceNumber: SafeJson.asText(json['invoice_number']),
      invoiceStatus: SafeJson.asText(json['invoice_status']),
      deliveryDate: SafeJson.asDay(json['delivery_date']),
      warrantyStart: SafeJson.asDay(json['warranty_start']),
      warrantyEnd: SafeJson.asDay(json['warranty_end']),
      notes: SafeJson.asText(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_id': customerId,
        'sale_number': saleNumber,
        if (saleDate != null) 'sale_date': saleDate!.toIso8601String(),
        'sale_type': saleType,
        'status': status,
        'payment_mode': paymentMode,
        'is_emi': emi,
        'subtotal_amount': subtotal,
        'discount_amount': discountAmount,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'paid_amount': paidAmount,
        'balance_amount': balanceAmount,
        'delivery_date': deliveryDate?.toIso8601String(),
        'warranty_start': warrantyStart?.toIso8601String(),
        'warranty_end': warrantyEnd?.toIso8601String(),
        'notes': notes,
      };

  /// Customer name from the joined customer row.
  String get customerName {
    final dynamic c = customer;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '-');
    return c?.toString() ?? '-';
  }

  /// Primary vehicle line (first line of type `vehicle`).
  SaleLineItemModel? get vehicleLine {
    for (final SaleLineItemModel item in lineItems) {
      if (item.itemType == 'vehicle') return item;
    }
    return null;
  }
}

String? _firstInvoiceId(dynamic invoices) {
  final List<dynamic> list = SafeJson.asList(invoices);
  if (list.isEmpty) return null;
  final dynamic first = list.first;
  if (first is Map) return SafeJson.asId(first['id']);
  return null;
}
