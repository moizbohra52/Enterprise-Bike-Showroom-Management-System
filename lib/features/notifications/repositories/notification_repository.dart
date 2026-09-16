import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/features/notifications/models/notification_model.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for in-app notifications.
class NotificationRepository {
  NotificationRepository(this.supabase);

  final SupabaseService supabase;

  static const String _table = 'notifications';

  /// Unread count for the badge (current user; null = all showrooms).
  Future<int> unreadCount({String? showroomId}) async {
    dynamic builder = supabase
        .table(_table)
        .select('*')
        .eq('is_read', false);
    if (showroomId != null) builder = builder.eq('showroom_id', showroomId);
    try {
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final dynamic count = result.count;
      return SafeJson.asIntOr(count, 0);
    } catch (_) {
      return 0;
    }
  }

  /// Paginated list for the notifications page.
  Future<PaginatedResponse<NotificationModel>> list(
    PageQuery query, {
    bool unreadOnly = false,
  }) async {
    dynamic builder = supabase.table(_table).select('*');
    if (unreadOnly) builder = builder.eq('is_read', false);
    final String? type = SafeJson.asString(query.filters['type']);
    if (type != null && type.isNotEmpty) {
      builder = builder.eq('notification_type', type);
    }
    builder = builder.order('created_at', ascending: false);
    builder = builder.range(query.offset, query.end);
    final dynamic result = await (builder).count(CountOption.exact);
    // ignore: avoid_dynamic_calls
    final int total = SafeJson.asIntOr(result.count, 0);
    return PaginatedResponse<NotificationModel>.fromSupabase(
      SafeJson.asList(result),
      total: total,
      query: query,
      fromJson: (Map<String, dynamic> json) => NotificationModel.fromJson(json),
    );
  }

  /// Marks one notification read.
  Future<void> markRead(String id) async {
    await supabase
        .table(_table)
        .update(<String, dynamic>{'is_read': true})
        .eq('id', id);
  }

  /// Marks all notifications for the user as read.
  Future<void> markAllRead() async {
    await supabase
        .table(_table)
        .update(<String, dynamic>{'is_read': true})
        .eq('is_read', false);
  }
}
