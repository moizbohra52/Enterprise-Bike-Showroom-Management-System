import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A service line (part or labour).
class ServiceItemModel {
  ServiceItemModel({
    this.id,
    required this.itemType, // part | labour | other
    required this.name,
    this.partNumber = '',
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
    this.totalAmount = 0,
  });

  final String? id;
  final String itemType;
  final String name;
  final String partNumber;
  final num qty;
  final num unitPrice;
  final num discount;
  final num totalAmount;

  factory ServiceItemModel.fromJson(Map<String, dynamic> json) {
    return ServiceItemModel(
      id: SafeJson.asId(json['id']),
      itemType: SafeJson.asText(json['item_type'], fallback: 'labour'),
      name: SafeJson.asText(json['name']),
      partNumber: SafeJson.asText(json['part_number']),
      qty: SafeJson.asMoney(json['qty']),
      unitPrice: SafeJson.asMoney(json['unit_price']),
      discount: SafeJson.asMoney(json['discount_amount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'item_type': itemType,
        'name': name,
        'part_number': partNumber,
        'qty': qty,
        'unit_price': unitPrice,
        'discount_amount': discount,
        'total_amount': totalAmount,
      };
}

/// A service record (workshop job card).
class ServiceRecordModel extends BaseModel {
  ServiceRecordModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.customerId,
    this.customer,
    this.vehicleId,
    this.vehicle,
    required this.serviceNumber,
    this.serviceDate,
    this.status = 'in_progress',
    this.jobType = 'paid', // paid | free | warranty
    this.odometerIn,
    this.odometerOut,
    this.problemDescription = '',
    this.workDone = '',
    this.subtotal = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.completedAt,
    this.items = const <ServiceItemModel>[],
  });

  final String? showroomId;
  final String? customerId;
  final dynamic customer;
  final String? vehicleId;
  final dynamic vehicle;
  final String serviceNumber;
  final DateTime? serviceDate;
  // in_progress | waiting_parts | ready | delivered | cancelled
  final String status;
  final String jobType;
  final num? odometerIn;
  final num? odometerOut;
  final String problemDescription;
  final String workDone;
  final num subtotal;
  final num discountAmount;
  final num taxAmount;
  final num totalAmount;
  final num paidAmount;
  final DateTime? completedAt;
  final List<ServiceItemModel> items;

  factory ServiceRecordModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return ServiceRecordModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerId: SafeJson.asId(json['customer_id']),
      customer: json['customer'],
      vehicleId: SafeJson.asId(json['vehicle_id']),
      vehicle: json['vehicle'],
      serviceNumber: SafeJson.asText(json['service_number']),
      serviceDate: SafeJson.asDay(json['service_date']),
      status: SafeJson.asText(json['status'], fallback: 'in_progress'),
      jobType: SafeJson.asText(json['job_type'], fallback: 'paid'),
      odometerIn: SafeJson.asNum(json['odometer_in']),
      odometerOut: SafeJson.asNum(json['odometer_out']),
      problemDescription: SafeJson.asText(json['problem_description']),
      workDone: SafeJson.asText(json['work_done']),
      subtotal: SafeJson.asMoney(json['subtotal_amount']),
      discountAmount: SafeJson.asMoney(json['discount_amount']),
      taxAmount: SafeJson.asMoney(json['tax_amount']),
      totalAmount: SafeJson.asMoney(json['total_amount']),
      paidAmount: SafeJson.asMoney(json['paid_amount']),
      completedAt: SafeJson.asDate(json['completed_at']),
      items: <ServiceItemModel>[
        for (final dynamic row in SafeJson.asList(json['service_items']))
          ServiceItemModel.fromJson(SafeJson.asMap(row)),
      ],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_id': customerId,
        'vehicle_id': vehicleId,
        'service_number': serviceNumber,
        if (serviceDate != null)
          'service_date': serviceDate!.toIso8601String(),
        'status': status,
        'job_type': jobType,
        'odometer_in': odometerIn,
        'odometer_out': odometerOut,
        'problem_description': problemDescription,
        'work_done': workDone,
        'notes': null,
      };

  String get customerName {
    final dynamic c = customer;
    if (c is Map) return SafeJson.asText(SafeJson.asMap(c)['name'], fallback: '-');
    return c?.toString() ?? '-';
  }

  String get vehicleLabel {
    final dynamic v = vehicle;
    if (v is Map) {
      final Map<String, dynamic> vm = SafeJson.asMap(v);
      return '${SafeJson.asText(vm['registration_number'])} · '
          '${SafeJson.asText(vm['chassis_number'])}';
    }
    return v?.toString() ?? '-';
  }
}

/// A free-service plan (mileage/time-based, offered with products).
class FreeServicePlanModel extends BaseModel {
  FreeServicePlanModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.productId,
    this.productName = '',
    required this.name,
    this.serviceKm = 0,
    this.serviceDays = 90,
    this.includedServices = '',
    this.isActive = true,
  });

  final String? productId;
  final String productName;
  final String name;
  final num serviceKm;
  final int serviceDays;
  final String includedServices;
  final bool isActive;

  factory FreeServicePlanModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return FreeServicePlanModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      productId: SafeJson.asId(json['product_id']),
      productName: SafeJson.asText(json['product_name']),
      name: SafeJson.asText(json['name']),
      serviceKm: SafeJson.asMoney(json['service_km']),
      serviceDays: SafeJson.asIntOr(json['service_days'], 90),
      includedServices: SafeJson.asText(json['included_services']),
      isActive: SafeJson.asBoolOr(json['is_active'], true),
    );
  }
}
