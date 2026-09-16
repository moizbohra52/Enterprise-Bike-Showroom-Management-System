import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/documents/models/attachment_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for attachments (documents).
class AttachmentRepository {
  AttachmentRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<AttachmentModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('attachments')
          .select('*');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'file_name.ilike.%$term%,notes.ilike.%$term%,entity_type.ilike.%$term%',
        );
      }
      final String? type = SafeJson.asString(query.filters['entity_type']);
      if (type != null && type.isNotEmpty) {
        builder = builder.eq('entity_type', type);
      }
      final String? entityId =
          SafeJson.asString(query.filters['entity_id']);
      if (entityId != null && entityId.isNotEmpty) {
        builder = builder.eq('entity_id', entityId);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<AttachmentModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => AttachmentModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<AttachmentModel> create(Map<String, dynamic> payload) async {
    try {
      final dynamic row = await supabase
          .table('attachments')
          .insert(payload)
          .select()
          .single();
      return AttachmentModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<void> softDelete(String id) async {
    try {
      await supabase
          .table('attachments')
          .update(<String, dynamic>{
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Data access for the audit log (read-only in the app).
class AuditRepository {
  AuditRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<AuditLogModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('audit_log')
          .select('*');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'user_name.ilike.%$term%,entity_type.ilike.%$term%,action.ilike.%$term%',
        );
      }
      final String? action = SafeJson.asString(query.filters['action']);
      if (action != null && action.isNotEmpty) {
        builder = builder.eq('action', action);
      }
      final String? entityType =
          SafeJson.asString(query.filters['entity_type']);
      if (entityType != null && entityType.isNotEmpty) {
        builder = builder.eq('entity_type', entityType);
      }
      builder = builder.order('created_at', ascending: false);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<AuditLogModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => AuditLogModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Marker for downstream failures.
typedef AttachmentFlowException = AppException;
