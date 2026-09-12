import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for showrooms (tenant roots).
class ShowroomRepository {
  ShowroomRepository(this.supabase);

  final SupabaseService supabase;

  static const String _table = 'showrooms';

  Future<PaginatedResponse<ShowroomModel>> list(PageQuery query) async {
    try {
      var builder = supabase
          .table(_table)
          .select('*', count: CountOption.exact)
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or('name.ilike.%$term%,code.ilike.%$term%,city.ilike.%$term%');
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) builder = builder.eq('status', status);
      builder = query.orderBy == null
          ? builder.order('code', ascending: true)
          : builder.order(query.orderBy, ascending: query.ascending);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<ShowroomModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => ShowroomModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<List<ShowroomModel>> allActive() async {
    try {
      final dynamic rows =
          await supabase.table(_table).select().eq('status', 'active').order('name');
      return <ShowroomModel>[
        for (final dynamic r in SafeJson.asList(rows))
          if (r is Map) ShowroomModel.fromJson(SafeJson.asMap(r)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ShowroomModel?> getById(String id) async {
    try {
      final dynamic row =
          await supabase.table(_table).select().eq('id', id).maybeSingle();
      if (row is! Map) return null;
      return ShowroomModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ShowroomModel> create(Map<String, dynamic> payload) async {
    try {
      final dynamic row =
          await supabase.table(_table).insert(payload).select().single();
      // First showroom: create its default accounting accounts.
      final String? id = row is Map ? SafeJson.asId(row['id']) : null;
      if (id != null) {
        await supabase.rpc('ensure_showroom_accounts',
            params: <String, dynamic>{'p_showroom_id': id});
      }
      return ShowroomModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ShowroomModel> update(String id, Map<String, dynamic> patch) async {
    try {
      final dynamic row = await supabase
          .table(_table)
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return ShowroomModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

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
                'Showroom no longer exists on the server.');
          }
          return SyncOperationResult.ok(serverId: operation.entityId);
        } catch (e) {
          return _map(e);
        }
      default:
        return SyncOperationResult.fail(
            'Unsupported showroom operation: ${operation.operation.value}');
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
