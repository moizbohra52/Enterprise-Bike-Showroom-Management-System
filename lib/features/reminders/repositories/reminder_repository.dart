import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/reminders/models/reminder_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for reminders.
class ReminderRepository {
  ReminderRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<ReminderModel>> list(PageQuery query) async {
    try {
      var builder = supabase
          .table('reminders')
          .select(
            '*, customer:customers(name, phone)',
            count: CountOption.exact,
          )
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'title.ilike.%$term%,message.ilike.%$term%,customer:customers(name).ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      final String? type = SafeJson.asString(query.filters['type']);
      if (type != null && type.isNotEmpty) {
        builder = builder.eq('type', type);
      }
      final String? showroomId =
          SafeJson.asString(query.filters['showroom_id']);
      if (showroomId != null && showroomId.isNotEmpty) {
        builder = builder.eq('showroom_id', showroomId);
      }
      builder = query.orderBy == null
          ? builder.order('reminder_date', ascending: true)
          : builder.order(query.orderBy, ascending: query.ascending);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<ReminderModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => ReminderModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ReminderModel> create(Map<String, dynamic> payload) async {
    try {
      final dynamic row = await supabase
          .table('reminders')
          .insert(payload)
          .select()
          .single();
      return ReminderModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ReminderModel> setStatus(String id, String status) async {
    try {
      final dynamic row = await supabase
          .table('reminders')
          .update(<String, dynamic>{
            'status': status,
            if (status == 'done')
              'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();
      return ReminderModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Regenerates due reminders (EMI + service) from the server cron
  /// (also runs nightly via pg_cron).
  Future<void> regenerate() async {
    try {
      await supabase.rpc('create_emi_reminders');
      await supabase.rpc('create_service_reminders');
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Marker for downstream failures.
typedef ReminderFlowException = AppException;
