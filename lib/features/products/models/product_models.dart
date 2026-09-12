import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A bike brand (Honda, TVS, Hero, …).
class BrandModel extends BaseModel {
  BrandModel({super.id, super.createdAt, super.updatedAt, required this.name, this.status = 'active'});

  final String name;
  final String status;

  factory BrandModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return BrandModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      name: SafeJson.asText(json['name']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'name': name,
        'status': status,
      };

  BrandModel copyWith({String? id, String? name, String? status}) {
    return BrandModel(
      id: id ?? this.id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      name: name ?? this.name,
      status: status ?? this.status,
    );
  }
}

/// A color option for a product.
class ProductColorModel extends BaseModel {
  ProductColorModel({
    super.id,
    super.createdAt,
    required this.productId,
    required this.colorName,
    required this.hexCode,
  });

  final String productId;
  final String colorName;
  final String hexCode;

  factory ProductColorModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return ProductColorModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      productId: SafeJson.asText(json['product_id']),
      colorName: SafeJson.asText(json['color_name']),
      hexCode: SafeJson.asText(json['hex_code']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'product_id': productId,
        'color_name': colorName,
        'hex_code': hexCode,
      };
}

/// An image entry for a product.
class ProductImageModel extends BaseModel {
  ProductImageModel({
    super.id,
    super.createdAt,
    required this.productId,
    required this.imageUrl,
    this.thumbnailUrl,
    this.isPrimary = false,
    this.sortOrder = 0,
    this.watermarkEnabled = false,
  });

  final String productId;
  final String imageUrl;
  final String? thumbnailUrl;
  final bool isPrimary;
  final int sortOrder;
  final bool watermarkEnabled;

  factory ProductImageModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return ProductImageModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      productId: SafeJson.asText(json['product_id']),
      imageUrl: SafeJson.asText(json['image_url']),
      thumbnailUrl: SafeJson.asString(json['thumbnail_url']),
      isPrimary: SafeJson.asBoolOr(json['is_primary'], false),
      sortOrder: SafeJson.asIntOr(json['sort_order'], 0),
      watermarkEnabled: SafeJson.asBoolOr(json['watermark_enabled'], false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'product_id': productId,
        'image_url': imageUrl,
        'thumbnail_url': thumbnailUrl,
        'is_primary': isPrimary,
        'sort_order': sortOrder,
        'watermark_enabled': watermarkEnabled,
      };
}

/// A bike/product record.
class ProductModel extends BaseModel {
  ProductModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.brandId,
    this.brand,
    required this.name,
    this.model = '',
    this.variant = '',
    this.category = '',
    this.engineCc,
    this.fuelType = '',
    this.transmission = '',
    this.mileage,
    this.description = '',
    this.basePrice = 0,
    this.sellingPrice = 0,
    this.taxRate = 18,
    this.warrantyMonths = 12,
    this.status = 'active',
    this.colors = const <ProductColorModel>[],
    this.images = const <ProductImageModel>[],
  });

  final String? brandId;
  final BrandModel? brand;
  final String name;
  final String model;
  final String variant;
  final String category;
  final num? engineCc;
  final String fuelType;
  final String transmission;
  final num? mileage;
  final String description;
  final num basePrice;
  final num sellingPrice;
  final num taxRate;
  final int warrantyMonths;
  final String status;
  final List<ProductColorModel> colors;
  final List<ProductImageModel> images;

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    final Map<String, dynamic>? brandJson = json['brand'] is Map
        ? SafeJson.asMap(json['brand'])
        : null;
    return ProductModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      brandId: SafeJson.asId(json['brand_id']),
      brand: brandJson != null ? BrandModel.fromJson(brandJson) : null,
      name: SafeJson.asText(json['name']),
      model: SafeJson.asText(json['model']),
      variant: SafeJson.asText(json['variant']),
      category: SafeJson.asText(json['category']),
      engineCc: SafeJson.asNum(json['engine_cc']),
      fuelType: SafeJson.asText(json['fuel_type']),
      transmission: SafeJson.asText(json['transmission']),
      mileage: SafeJson.asNum(json['mileage']),
      description: SafeJson.asText(json['description']),
      basePrice: SafeJson.asMoney(json['base_price']),
      sellingPrice: SafeJson.asMoney(json['selling_price']),
      taxRate: SafeJson.asNum(json['tax_rate']) ?? 18,
      warrantyMonths: SafeJson.asIntOr(json['warranty_months'], 12),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      colors: <ProductColorModel>[
        for (final dynamic c in SafeJson.asList(json['product_colors']))
          if (c is Map) ProductColorModel.fromJson(SafeJson.asMap(c)),
      ],
      images: <ProductImageModel>[
        for (final dynamic i in SafeJson.asList(json['product_images']))
          if (i is Map) ProductImageModel.fromJson(SafeJson.asMap(i)),
      ],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'brand_id': brandId,
        'name': name,
        'model': model,
        'variant': variant,
        'category': category,
        'engine_cc': engineCc,
        'fuel_type': fuelType,
        'transmission': transmission,
        'mileage': mileage,
        'description': description,
        'base_price': basePrice,
        'selling_price': sellingPrice,
        'tax_rate': taxRate,
        'warranty_months': warrantyMonths,
        'status': status,
      };

  /// Primary image storage path (or first).
  String? get primaryImageUrl {
    for (final ProductImageModel image in images) {
      if (image.isPrimary) return image.imageUrl;
    }
    return images.isNotEmpty ? images.first.imageUrl : null;
  }

  String get fullName {
    final List<String> parts = <String>[
      brand?.name ?? '',
      name,
      if (model.isNotEmpty) model,
      if (variant.isNotEmpty) variant,
    ].where((String p) => p.isNotEmpty).toList();
    return parts.join(' ');
  }
}
