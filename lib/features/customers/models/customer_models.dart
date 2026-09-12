import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A customer (retail / dealer / corporate / financier).
class CustomerModel extends BaseModel {
  CustomerModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.customerCode = '',
    required this.name,
    this.phone = '',
    this.alternatePhone = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.customerType = 'retail',
    this.notes = '',
    this.status = 'active',
    this.outstanding = 0,
    this.vehicleCount = 0,
  });

  final String? showroomId;
  final String customerCode;
  final String name;
  final String phone;
  final String alternatePhone;
  final String email;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String customerType;
  final String notes;
  final String status;

  /// Sum of open invoice amounts (populated by list queries).
  final num outstanding;

  /// Number of vehicles owned (populated by list queries).
  final int vehicleCount;

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return CustomerModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerCode: SafeJson.asText(json['customer_code']),
      name: SafeJson.asText(json['name']),
      phone: SafeJson.asText(json['phone']),
      alternatePhone: SafeJson.asText(json['alternate_phone']),
      email: SafeJson.asText(json['email']),
      address: SafeJson.asText(json['address']),
      city: SafeJson.asText(json['city']),
      state: SafeJson.asText(json['state']),
      pincode: SafeJson.asText(json['pincode']),
      customerType: SafeJson.asText(json['customer_type'], fallback: 'retail'),
      notes: SafeJson.asText(json['notes']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      outstanding: SafeJson.asMoney(json['outstanding']),
      vehicleCount: SafeJson.asIntOr(json['vehicle_count'], 0),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_code': customerCode,
        'name': name,
        'phone': phone,
        'alternate_phone': alternatePhone,
        'email': email,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'customer_type': customerType,
        'notes': notes,
        'status': status,
      };

  CustomerModel copyWith({
    String? id,
    String? customerCode,
    String? name,
    String? phone,
    String? alternatePhone,
    String? email,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? customerType,
    String? notes,
    String? status,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      showroomId: showroomId,
      customerCode: customerCode ?? this.customerCode,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      email: email ?? this.email,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      customerType: customerType ?? this.customerType,
      notes: notes ?? this.notes,
      status: status ?? this.status,
    );
  }

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

/// A vehicle owned by a customer (created at sale delivery).
class CustomerVehicleModel extends BaseModel {
  CustomerVehicleModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    required this.customerId,
    this.inventoryId,
    this.productId,
    this.product,
    this.registrationNumber = '',
    this.registrationDate,
    this.chassisNumber = '',
    this.engineNumber = '',
    this.purchaseDate,
    this.deliveryDate,
    this.currentOdometer = 0,
    this.warrantyStart,
    this.warrantyEnd,
    this.insuranceStart,
    this.insuranceEnd,
    this.nextServiceDate,
    this.nextServiceKm,
    this.status = 'active',
  });

  final String customerId;
  final String? inventoryId;
  final String? productId;
  final dynamic product;
  final String registrationNumber;
  final DateTime? registrationDate;
  final String chassisNumber;
  final String engineNumber;
  final DateTime? purchaseDate;
  final DateTime? deliveryDate;
  final num currentOdometer;
  final DateTime? warrantyStart;
  final DateTime? warrantyEnd;
  final DateTime? insuranceStart;
  final DateTime? insuranceEnd;
  final DateTime? nextServiceDate;
  final num? nextServiceKm;
  final String status;

  factory CustomerVehicleModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return CustomerVehicleModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      customerId: SafeJson.asText(json['customer_id']),
      inventoryId: SafeJson.asId(json['inventory_id']),
      productId: SafeJson.asId(json['product_id']),
      product: json['product'],
      registrationNumber: SafeJson.asText(json['registration_number']),
      registrationDate: SafeJson.asDay(json['registration_date']),
      chassisNumber: SafeJson.asText(json['chassis_number']),
      engineNumber: SafeJson.asText(json['engine_number']),
      purchaseDate: SafeJson.asDay(json['purchase_date']),
      deliveryDate: SafeJson.asDay(json['delivery_date']),
      currentOdometer: SafeJson.asMoney(json['current_odometer']),
      warrantyStart: SafeJson.asDay(json['warranty_start']),
      warrantyEnd: SafeJson.asDay(json['warranty_end']),
      insuranceStart: SafeJson.asDay(json['insurance_start']),
      insuranceEnd: SafeJson.asDay(json['insurance_end']),
      nextServiceDate: SafeJson.asDay(json['next_service_date']),
      nextServiceKm: SafeJson.asNum(json['next_service_km']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'customer_id': customerId,
        'inventory_id': inventoryId,
        'product_id': productId,
        'registration_number': registrationNumber,
        if (registrationDate != null)
          'registration_date': registrationDate!.toIso8601String(),
        'chassis_number': chassisNumber,
        'engine_number': engineNumber,
        if (purchaseDate != null)
          'purchase_date': purchaseDate!.toIso8601String(),
        if (deliveryDate != null)
          'delivery_date': deliveryDate!.toIso8601String(),
        'current_odometer': currentOdometer,
        if (warrantyStart != null)
          'warranty_start': warrantyStart!.toIso8601String(),
        if (warrantyEnd != null)
          'warranty_end': warrantyEnd!.toIso8601String(),
        if (insuranceStart != null)
          'insurance_start': insuranceStart!.toIso8601String(),
        if (insuranceEnd != null)
          'insurance_end': insuranceEnd!.toIso8601String(),
        if (nextServiceDate != null)
          'next_service_date': nextServiceDate!.toIso8601String(),
        'next_service_km': nextServiceKm,
        'status': status,
      };

  /// Product label from the joined product row.
  String get productLabel {
    final dynamic p = product;
    if (p is Map) {
      final Map<String, dynamic> pm = SafeJson.asMap(p);
      final String brand = SafeJson.asText(pm['brand']);
      final String name = SafeJson.asText(pm['name']);
      final String model = SafeJson.asText(pm['model']);
      return [brand, name, model]
          .where((String s) => s.isNotEmpty)
          .join(' ');
    }
    return p?.toString() ?? '-';
  }
}
