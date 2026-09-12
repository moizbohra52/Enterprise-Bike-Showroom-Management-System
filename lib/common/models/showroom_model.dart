import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A physical showroom (tenant root).
///
/// Every business record is scoped by `showroom_id`; users may access only
/// the showrooms they are assigned to (SUPER ADMIN sees all).
class ShowroomModel extends BaseModel {
  ShowroomModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    required this.name,
    required this.code,
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.phone = '',
    this.email = '',
    this.gstNumber = '',
    this.panNumber = '',
    this.invoicePrefix = 'INV',
    this.logoUrl,
    this.status = 'active',
    this.settings = const <String, dynamic>{},
  });

  final String name;
  final String code;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String phone;
  final String email;
  final String gstNumber;
  final String panNumber;

  /// Prefix used when generating invoice/document numbers.
  final String invoicePrefix;
  final String? logoUrl;
  final String status;
  final Map<String, dynamic> settings;

  factory ShowroomModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return ShowroomModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      name: SafeJson.asText(json['name']),
      code: SafeJson.asText(json['code']),
      address: SafeJson.asText(json['address']),
      city: SafeJson.asText(json['city']),
      state: SafeJson.asText(json['state']),
      pincode: SafeJson.asText(json['pincode']),
      phone: SafeJson.asText(json['phone']),
      email: SafeJson.asText(json['email']),
      gstNumber: SafeJson.asText(json['gst_number']),
      panNumber: SafeJson.asText(json['pan_number']),
      invoicePrefix: SafeJson.asText(json['invoice_prefix'], fallback: 'INV'),
      logoUrl: SafeJson.asString(json['logo_url']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      settings: SafeJson.asMap(json['settings']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'name': name,
        'code': code,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'phone': phone,
        'email': email,
        'gst_number': gstNumber,
        'pan_number': panNumber,
        'invoice_prefix': invoicePrefix,
        'logo_url': logoUrl,
        'status': status,
        'settings': settings,
      };

  ShowroomModel copyWith({
    String? id,
    String? name,
    String? code,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? phone,
    String? email,
    String? gstNumber,
    String? panNumber,
    String? invoicePrefix,
    String? logoUrl,
    String? status,
    Map<String, dynamic>? settings,
  }) {
    return ShowroomModel(
      id: id ?? this.id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      name: name ?? this.name,
      code: code ?? this.code,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gstNumber: gstNumber ?? this.gstNumber,
      panNumber: panNumber ?? this.panNumber,
      invoicePrefix: invoicePrefix ?? this.invoicePrefix,
      logoUrl: logoUrl ?? this.logoUrl,
      status: status ?? this.status,
      settings: settings ?? this.settings,
    );
  }

  /// Full display address.
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
