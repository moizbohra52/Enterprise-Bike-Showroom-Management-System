import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A supplier (brand distributor / parts vendor).
class SupplierModel extends BaseModel {
  SupplierModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.name = '',
    this.contactPerson = '',
    this.phone = '',
    this.alternatePhone = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.gstin = '',
    this.paymentTermsDays = 30,
    this.notes = '',
    this.status = 'active',
  });

  final String name;
  final String contactPerson;
  final String phone;
  final String alternatePhone;
  final String email;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String gstin;
  final int paymentTermsDays;
  final String notes;
  final String status; // active | inactive

  factory SupplierModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return SupplierModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      name: SafeJson.asText(json['name']),
      contactPerson: SafeJson.asText(json['contact_person']),
      phone: SafeJson.asText(json['phone']),
      alternatePhone: SafeJson.asText(json['alternate_phone']),
      email: SafeJson.asText(json['email']),
      address: SafeJson.asText(json['address']),
      city: SafeJson.asText(json['city']),
      state: SafeJson.asText(json['state']),
      pincode: SafeJson.asText(json['pincode']),
      gstin: SafeJson.asText(json['gstin']),
      paymentTermsDays: SafeJson.asIntOr(json['payment_terms_days'], 30),
      notes: SafeJson.asText(json['notes']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'name': name,
        'contact_person': contactPerson,
        'phone': phone,
        'alternate_phone': alternatePhone,
        'email': email,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'gstin': gstin,
        'payment_terms_days': paymentTermsDays,
        'notes': notes,
        'status': status,
      };

  String get fullAddress {
    final List<String> parts = <String>[
      if (address.isNotEmpty) address,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
      if (pincode.isNotEmpty) pincode,
    ];
    return parts.join(', ');
  }
}

/// A purchase line.
class PurchaseLineModel {
  PurchaseLineModel({
    this.id,
    required this.productId,
    this.productName = '',
    this.color = '',
    this.lineNumber = 1,
    required this.qty,
    required this.unitCost,
    this.taxRate = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.receivedQty = 0,
  });

  final String? id;
  final String productId;
  final String productName;
  final String color;
  final int lineNumber;
  final num qty;
  final num unitCost;
  final num taxRate;
  final num taxAmount;
  final num totalAmount;
  final num receivedQty;

  factory PurchaseLineModel.fromJson(Map<String, dynamic> json) {
    return PurchaseLineModel(
      id: SafeJson.asId(json['id']),
      productId: SafeJson.asText(json['product_id']),
      productName: SafeJson.asText(json['product_name']),
      color: SafeJson.asText(json['color']),
      lineNumber: SafeJson.asIntOr(json['line_number'], 1),
      qty: SafeJson.asMoney(json['qty']),
      unitCost: SafeJson.asMoney(json['unit_cost']),
      taxRate: SafeJson.asMoney(json['tax_rate']),
      taxAmount: SafeJson.asMoney(json['tax_amount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
      receivedQty: SafeJson.asMoney(json['received_qty']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'product_id': productId,
        'product_name': productName,
        'color': color,
        'line_number': lineNumber,
        'qty': qty,
        'unit_cost': unitCost,
        'tax_rate': taxRate,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'received_qty': receivedQty,
      };
}

/// A purchase order / received purchase.
class PurchaseModel extends BaseModel {
  PurchaseModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.supplierId,
    this.supplier,
    required this.purchaseNumber,
    this.orderDate,
    this.expectedDate,
    this.receivedDate,
    this.status = 'ordered',
    this.paymentStatus = 'unpaid',
    this.subtotal = 0,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.outstandingAmount = 0,
    this.lines = const <PurchaseLineModel>[],
    this.notes,
  });

  final String? showroomId;
  final String? supplierId;
  final dynamic supplier;
  final String purchaseNumber;
  final DateTime? orderDate;
  final DateTime? expectedDate;
  final DateTime? receivedDate;
  final String status; // ordered | partial | received | cancelled
  final String paymentStatus; // unpaid | partial | paid
  final num subtotal;
  final num taxAmount;
  final num discountAmount;
  final num totalAmount;
  final num paidAmount;
  final num outstandingAmount;
  final List<PurchaseLineModel> lines;
  final String? notes;

  factory PurchaseModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return PurchaseModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      supplierId: SafeJson.asId(json['supplier_id']),
      supplier: json['supplier'],
      purchaseNumber: SafeJson.asText(json['purchase_number']),
      orderDate: SafeJson.asDay(json['order_date']),
      expectedDate: SafeJson.asDay(json['expected_date']),
      receivedDate: SafeJson.asDay(json['received_date']),
      status: SafeJson.asText(json['status'], fallback: 'ordered'),
      paymentStatus:
          SafeJson.asText(json['payment_status'], fallback: 'unpaid'),
      subtotal: SafeJson.asMoney(json['subtotal_amount']),
      taxAmount: SafeJson.asMoney(json['tax_amount']),
      discountAmount: SafeJson.asMoney(json['discount_amount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
      paidAmount: SafeJson.asMoney(json['paid_amount']),
      outstandingAmount: SafeJson.asMoney(json['outstanding_amount']),
      lines: <PurchaseLineModel>[
        for (final dynamic row in SafeJson.asList(json['purchase_items']))
          PurchaseLineModel.fromJson(SafeJson.asMap(row)),
      ],
      notes: SafeJson.asText(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'supplier_id': supplierId,
        'purchase_number': purchaseNumber,
        if (orderDate != null)
          'order_date': orderDate!.toIso8601String(),
        if (expectedDate != null)
          'expected_date': expectedDate!.toIso8601String(),
        'status': status,
        'payment_status': paymentStatus,
        'subtotal_amount': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'total_amount': totalAmount,
        'paid_amount': paidAmount,
        'outstanding_amount': outstandingAmount,
        'notes': notes,
      };

  String get supplierName {
    final dynamic s = supplier;
    if (s is Map) {
      return SafeJson.asText(SafeJson.asMap(s)['name'], fallback: '-');
    }
    return s?.toString() ?? '-';
  }

  num get totalReceived =>
      lines.fold(0, (num sum, PurchaseLineModel l) => sum + l.receivedQty);
}
