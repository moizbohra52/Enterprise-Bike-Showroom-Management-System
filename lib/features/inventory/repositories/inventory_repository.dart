import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/inventory/models/inventory_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for inventory, transfers and stock history.
///
/// Critical multi-step operations (transfer, adjustment) go through
/// server-side RPCs so the DB stays consistent.
class InventoryRepository {
  InventoryRepository(this.supabase);

  final SupabaseService supabase;

  static const String _table = 'inventory';

  Future<PaginatedResponse<InventoryModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table(_table)
          .select('*, product:products(name, model, brand:brands(name))');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'chassis_number.ilike.%$term%,engine_number.ilike.%$term%,stock_code.ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) builder = builder.eq('status', status);
      final String? showroomId =
          SafeJson.asString(query.filters['showroom_id']);
      if (showroomId != null && showroomId.isNotEmpty) {
        builder = builder.eq('showroom_id', showroomId);
      }
      final String? productId = SafeJson.asString(query.filters['product_id']);
      if (productId != null && productId.isNotEmpty) {
        builder = builder.eq('product_id', productId);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<InventoryModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => InventoryModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<InventoryModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table(_table)
          .select(
              '*, product:products(name, model, variant, brand:brands(name)), product_color:product_colors(*)')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return InventoryModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Stock-in: creates the inventory row (chassis/engine uniqueness enforced
  /// by the DB).
  Future<InventoryModel> stockIn(Map<String, dynamic> payload) async {
    try {
      final dynamic row = await supabase.table(_table).insert(payload).select().single();
      return InventoryModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Transfers bikes to another showroom (atomic RPC).
  Future<Map<String, dynamic>> transfer({
    required List<String> inventoryIds,
    required String toShowroomId,
    DateTime? transferDate,
    String? notes,
  }) async {
    return supabase.rpc('transfer_inventory', params: <String, dynamic>{
      'p_payload': <String, dynamic>{
        'inventory_ids': inventoryIds,
        'to_showroom_id': toShowroomId,
        'transfer_date':
            (transferDate ?? DateTime.now()).toIso8601String(),
        'notes': notes,
      },
    });
  }

  /// Reserves / releases / status change (atomic RPC).
  Future<Map<String, dynamic>> adjust({
    required String inventoryId,
    required String newStatus,
    String? location,
    String? reason,
  }) async {
    return supabase.rpc('adjust_stock', params: <String, dynamic>{
      'p_payload': <String, dynamic>{
        'inventory_id': inventoryId,
        'new_status': newStatus,
        'location': location,
        'reason': reason,
      },
    });
  }

  /// Stock movement history for one bike.
  Future<List<StockHistoryModel>> history(String inventoryId) async {
    try {
      final dynamic rows = await supabase
          .table('stock_history')
          .select()
          .eq('inventory_id', inventoryId)
          .order('created_at', ascending: false)
          .limit(100);
      return <StockHistoryModel>[
        for (final dynamic r in SafeJson.asList(rows));
          if (r is Map) StockHistoryModel.fromJson(SafeJson.asMap(r)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<List<StockTransferModel>> transfers({int limit = 50}) async {
    try {
      final dynamic rows = await supabase
          .table('stock_transfers')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return <StockTransferModel>[
        for (final dynamic r in SafeJson.asList(rows));
          if (r is Map) StockTransferModel.fromJson(SafeJson.asMap(r)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ------------------------------------------------------- offline sync ops

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
          return _map(e);
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
                'Inventory record no longer exists on the server.');
          }
          return SyncOperationResult.ok(serverId: operation.entityId);
        } catch (e) {
          return _map(e);
        }
      default:
        // Transfers/adjustments/sales must run as server RPCs, never from
        // the offline queue.
        return SyncOperationResult.fail(
            'Stock movements require a connection (server transaction).');
    }
  }

  SyncOperationResult _map(Object e) {
    final AppException mapped = ErrorMapper.map(e);
    if (mapped is ConflictException || mapped is ValidationException) {
      return SyncOperationResult.conflictWith(mapped.message);
    }
    return SyncOperationResult.fail(mapped.message);
  }
}
