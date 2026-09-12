import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/products/models/product_models.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';

/// Data access for brands, products, colors and images.
class ProductRepository {
  ProductRepository(this.supabase);

  final SupabaseService supabase;

  static const String _table = 'products';

  // ---------------------------------------------------------------- brands

  Future<List<BrandModel>> listBrands() async {
    try {
      final dynamic rows = await supabase
          .table('brands')
          .select()
          .eq('status', 'active')
          .order('name');
      return <BrandModel>[
        for (final dynamic r in SafeJson.asList(rows))
          if (r is Map) BrandModel.fromJson(SafeJson.asMap(r)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<BrandModel> createBrand(String name) async {
    try {
      final dynamic row =
          await supabase.table('brands').insert(<String, dynamic>{'name': name}).select().single();
      return BrandModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ------------------------------------------------------------- products

  Future<PaginatedResponse<ProductModel>> list(PageQuery query) async {
    try {
      var builder = supabase
          .table(_table)
          .select('*, brand:brands(*)', count: CountOption.exact)
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or('name.ilike.%$term%,model.ilike.%$term%,variant.ilike.%$term%');
      }
      final String? brandId = SafeJson.asString(query.filters['brand_id']);
      if (brandId != null && brandId.isNotEmpty) {
        builder = builder.eq('brand_id', brandId);
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) builder = builder.eq('status', status);
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<ProductModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => ProductModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ProductModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table(_table)
          .select('*, brand:brands(*), product_colors(*), product_images(*)')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return ProductModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ProductModel> create(Map<String, dynamic> payload) async {
    try {
      final dynamic row =
          await supabase.table(_table).insert(payload).select().single();
      return ProductModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ProductModel> update(String id, Map<String, dynamic> patch) async {
    try {
      final dynamic row = await supabase
          .table(_table)
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return ProductModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<void> softDelete(String id) async {
    try {
      await supabase.table(_table).update(<String, dynamic>{'status': 'inactive'}).eq('id', id);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // --------------------------------------------------------------- colors

  Future<void> replaceColors(String productId, List<ProductColorModel> colors) async {
    try {
      await supabase.table('product_colors').delete().eq('product_id', productId);
      for (final ProductColorModel color in colors) {
        await supabase.table('product_colors').insert(<String, dynamic>{
          'product_id': productId,
          'color_name': color.colorName,
          'hex_code': color.hexCode,
        });
      }
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // --------------------------------------------------------------- images

  Future<void> upsertImage(ProductImageModel image) async {
    try {
      await supabase.table('product_images').insert(<String, dynamic>{
        'product_id': image.productId,
        'image_url': image.imageUrl,
        'thumbnail_url': image.thumbnailUrl,
        'is_primary': image.isPrimary,
        'sort_order': image.sortOrder,
        'watermark_enabled': image.watermarkEnabled,
      });
      if (image.isPrimary) {
        await supabase
            .table('product_images')
            .update(<String, dynamic>{'is_primary': false})
            .eq('product_id', image.productId)
            .neq('image_url', image.imageUrl);
      }
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<void> deleteImage(String productId, String imageUrl) async {
    try {
      await supabase
          .table('product_images')
          .delete()
          .eq('product_id', productId)
          .eq('image_url', imageUrl);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Free-service plan lookup (used by sale flow).
  Future<List<Map<String, dynamic>>> freeServicePlansForProduct(String productId) async {
    try {
      final dynamic rows = await supabase
          .table('free_service_plans')
          .select()
          .eq('product_id', productId)
          .order('service_number');
      return <Map<String, dynamic>>[
        for (final dynamic r in SafeJson.asList(rows))
          if (r is Map) SafeJson.asMap(r),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ------------------------------------------------------- offline sync ops

  /// Applies a queued product mutation while offline.
  Future<SyncOperationResult> applySyncOp(SyncQueueEntry operation) async {
    switch (operation.operation) {
      case SyncOperation.create:
        try {
          final dynamic row = await supabase
              .table(_table)
              .insert(operation.payload)
              .select()
              .single();
          return SyncOperationResult.ok(
              serverId: row is Map ? SafeJson.asId(row['id']) : null);
        } catch (e) {
          return _mapSyncFailure(e);
        }
      case SyncOperation.update:
        try {
          final dynamic row = await supabase
              .table(_table)
              .update(operation.payload)
              .eq('id', operation.entityId)
              .select()
              .maybeSingle();
          if (row == null) {
            return SyncOperationResult.conflictWith(
                'Product no longer exists on the server.');
          }
          return SyncOperationResult.ok(serverId: operation.entityId);
        } catch (e) {
          return _mapSyncFailure(e);
        }
      case SyncOperation.delete:
        try {
          await supabase
              .table(_table)
              .update(<String, dynamic>{
                'status': 'inactive',
                'is_deleted': true,
                'deleted_at': DateTime.now().toIso8601String(),
              })
              .eq('id', operation.entityId);
          return SyncOperationResult.ok(serverId: operation.entityId);
        } catch (e) {
          return _mapSyncFailure(e);
        }
      case SyncOperation.payment:
      case SyncOperation.sale:
      case SyncOperation.service:
        return SyncOperationResult.fail(
            'Unsupported operation for products: ${operation.operation.value}');
    }
  }

  SyncOperationResult _mapSyncFailure(Object e) {
    final AppException mapped = ErrorMapper.map(e);
    if (mapped is ConflictException || mapped is ValidationException) {
      return SyncOperationResult.conflictWith(mapped.message);
    }
    return SyncOperationResult.fail(mapped.message);
  }
}
