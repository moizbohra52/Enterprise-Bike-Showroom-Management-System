import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// One physical bike in stock (tracked individually by chassis/engine no.).
class InventoryModel extends BaseModel {
  InventoryModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    required this.productId,
    this.colorId,
    this.product,
    this.color,
    this.stockCode = '',
    this.chassisNumber = '',
    this.engineNumber = '',
    this.manufacturingDate,
    this.modelYear,
    this.purchaseDate,
    this.purchasePrice = 0,
    this.status = 'available',
    this.location = '',
  });

  final String? showroomId;
  final String productId;
  final String? colorId;
  final dynamic product;
  final dynamic color;
  final String stockCode;
  final String chassisNumber;
  final String engineNumber;
  final DateTime? manufacturingDate;
  final int? modelYear;
  final DateTime? purchaseDate;
  final num purchasePrice;
  final String status;
  final String location;

  factory InventoryModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return InventoryModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      productId: SafeJson.asText(json['product_id']),
      colorId: SafeJson.asId(json['color_id']),
      product: json['product'],
      color: json['product_color'],
      stockCode: SafeJson.asText(json['stock_code']),
      chassisNumber: SafeJson.asText(json['chassis_number']),
      engineNumber: SafeJson.asText(json['engine_number']),
      manufacturingDate: SafeJson.asDay(json['manufacturing_date']),
      modelYear: SafeJson.asInt(json['model_year']),
      purchaseDate: SafeJson.asDay(json['purchase_date']),
      purchasePrice: SafeJson.asMoney(json['purchase_price']),
      status: SafeJson.asText(json['status'], fallback: 'available'),
      location: SafeJson.asText(json['location']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'product_id': productId,
        'color_id': colorId,
        'stock_code': stockCode,
        'chassis_number': chassisNumber,
        'engine_number': engineNumber,
        if (manufacturingDate != null)
          'manufacturing_date': manufacturingDate!.toIso8601String(),
        'model_year': modelYear,
        if (purchaseDate != null)
          'purchase_date': purchaseDate!.toIso8601String(),
        'purchase_price': purchasePrice,
        'status': status,
        'location': location,
      };

  /// Human readable product label (from joined product).
  String get productLabel {
    final dynamic p = product;
    if (p is Map) {
      final String brand = SafeJson.asString(p['brand']) == null
          ? ''
          : SafeJson.asText(SafeJson.asMap(p)['name']);
      final String name = SafeJson.asText(p['name']);
      final String model = SafeJson.asText(p['model']);
      return [brand, name, model].where((String s) => s.isNotEmpty).join(' ');
    }
    return p?.toString() ?? '-';
  }

  String get colorLabel {
    final dynamic c = color;
    if (c is Map) return SafeJson.asText(c['color_name']);
    return c?.toString() ?? '-';
  }
}

/// Stock transfer between showrooms.
class StockTransferModel extends BaseModel {
  StockTransferModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    required this.fromShowroomId,
    required this.toShowroomId,
    this.transferDate,
    this.status = 'pending',
    this.notes = '',
    this.inventoryIds = const <String>[],
  });

  final String fromShowroomId;
  final String toShowroomId;
  final DateTime? transferDate;
  final String status;
  final String notes;
  final List<String> inventoryIds;

  factory StockTransferModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return StockTransferModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      fromShowroomId: SafeJson.asText(json['from_showroom_id']),
      toShowroomId: SafeJson.asText(json['to_showroom_id']),
      transferDate: SafeJson.asDay(json['transfer_date']),
      status: SafeJson.asText(json['status'], fallback: 'pending'),
      notes: SafeJson.asText(json['notes']),
      inventoryIds: <String>[
        for (final dynamic v in SafeJson.asList(json['inventory_ids']))
          v.toString(),
      ],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'from_showroom_id': fromShowroomId,
        'to_showroom_id': toShowroomId,
        if (transferDate != null)
          'transfer_date': transferDate!.toIso8601String(),
        'status': status,
        'notes': notes,
        'inventory_ids': inventoryIds,
      };
}

/// Stock movement history (in/out/transfer/adjust/sale).
class StockHistoryModel extends BaseModel {
  StockHistoryModel({
    super.id,
    super.createdAt,
    required this.inventoryId,
    required this.action,
    this.fromStatus,
    this.toStatus,
    this.fromShowroomId,
    this.toShowroomId,
    this.notes = '',
    this.actorName = '',
  });

  final String inventoryId;
  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? fromShowroomId;
  final String? toShowroomId;
  final String notes;
  final String actorName;

  factory StockHistoryModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return StockHistoryModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      inventoryId: SafeJson.asText(json['inventory_id']),
      action: SafeJson.asText(json['action'], fallback: 'update'),
      fromStatus: SafeJson.asString(json['from_status']),
      toStatus: SafeJson.asString(json['to_status']),
      fromShowroomId: SafeJson.asId(json['from_showroom_id']),
      toShowroomId: SafeJson.asId(json['to_showroom_id']),
      notes: SafeJson.asText(json['notes']),
      actorName: SafeJson.asText(json['actor_name']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'inventory_id': inventoryId,
        'action': action,
        'from_status': fromStatus,
        'to_status': toStatus,
        'from_showroom_id': fromShowroomId,
        'to_showroom_id': toShowroomId,
        'notes': notes,
        'actor_name': actorName,
      };
}
