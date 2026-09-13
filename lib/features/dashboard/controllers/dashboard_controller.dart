import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

/// Aggregates the KPIs shown on the dashboard for the active showroom.
///
/// Counts are exact (`CountOption.exact`); money figures are summed on the
/// client from a bounded row set so the dashboard stays fast and does not
/// require an extra RPC. RLS keeps every read inside the user's showrooms.
class DashboardController extends GetxController {
  DashboardController(this.supabase, this.session, this.appState);

  final SupabaseService supabase;
  final SessionController session;
  final AppStateController appState;

  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;

  final RxInt salesToday = 0.obs;
  final RxDouble revenueToday = 0.0.obs;
  final RxDouble revenueMonth = 0.0.obs;
  final RxDouble outstanding = 0.0.obs;
  final RxInt customersTotal = 0.obs;
  final RxInt openServiceJobs = 0.obs;
  /// Units physically in stock (each inventory row is one bike).
  final RxInt stockUnits = 0.obs;
  final RxInt emiDueSoon = 0.obs;

  final RxList<Map<String, dynamic>> recentSales =
      <Map<String, dynamic>>[].obs;

  /// Maximum rows summed client-side for money KPIs.
  static const int _sumWindow = 1000;

  String get activeShowroomId => session.activeShowroomId;

  @override
  void onInit() {
    super.onInit();
    refresh();
    // Follow the working-showroom switch without a manual refresh.
    ever<String>(appState.activeShowroomId, (_) => refresh());
  }

  Future<void> refresh() async {
    if (isLoading.value) return;
    isLoading.value = true;
    errorMessage.value = '';
    final DateTime now = DateTime.now();
    final String today = _day(now);
    final String monthStart = _day(DateTime(now.year, now.month, 1));
    final String dueSoon =
        _day(now.add(const Duration(days: AppConfig.emiDueSoonReminderDays)));

    try {
      final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
        _count('sales', <String, String>{'sale_date': today}, dateField: 'sale_date', dateOp: _DateOp.eq),
        _sum('sales', 'total_amount', <String, String>{'sale_date': today}, dateField: 'sale_date', dateOp: _DateOp.gte),
        _sum('sales', 'total_amount', <String, String>{'sale_date': monthStart}, dateField: 'sale_date', dateOp: _DateOp.gte),
        _sum('invoices', 'outstanding_amount', <String, String>{'status': 'unpaid'}),
        _count('customers', const <String, String>{}),
        _count('service_records', const <String, String>{'service_status': 'open'}),
        _count('inventory', const <String, String>{'status': 'available'}),
        _count('emi_schedules', <String, String>{'due_date': dueSoon, 'status': 'pending'}, dateField: 'due_date', dateOp: _DateOp.lte),
        _recentSales(),
      ]);

      salesToday.value = results[0] as int;
      revenueToday.value = (results[1] as num).toDouble();
      revenueMonth.value = (results[2] as num).toDouble();
      outstanding.value = (results[3] as num).toDouble();
      customersTotal.value = results[4] as int;
      openServiceJobs.value = results[5] as int;
      stockUnits.value = results[6] as int;
      emiDueSoon.value = results[7] as int;
      recentSales.assignAll(
        SafeJson.asList(results[8])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false),
      );
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      AppLogger.error('DASHBOARD', 'kpi load failed', error: e);
    } finally {
      isLoading.value = false;
    }
  }

  Map<String, String> _scoped(Map<String, String> filters) {
    return <String, String>{
      ...filters,
      if (activeShowroomId.isNotEmpty) 'showroom_id': activeShowroomId,
    };
  }

  Future<int> _count(
    String table,
    Map<String, String> filters, {
    String? dateField,
    _DateOp dateOp = _DateOp.eq,
  }) async {
    try {
      dynamic builder = supabase
          .table(table)
          .select('id', count: CountOption.exact)
          .limit(1);
      builder = _applyFilters(builder, _scoped(filters), dateField, dateOp);
      final dynamic result = await builder;
      // PostgrestList carries `.count` when CountOption.exact is used.
      // ignore: avoid_dynamic_calls
      return SafeJson.asIntOr(result.count, 0);
    } catch (e) {
      AppLogger.warning('DASHBOARD', 'count($table) failed', error: e);
      return 0;
    }
  }

  Future<num> _sum(
    String table,
    String column,
    Map<String, String> filters, {
    String? dateField,
    _DateOp dateOp = _DateOp.eq,
  }) async {
    try {
      dynamic builder = supabase.table(table).select(column).limit(_sumWindow);
      builder = _applyFilters(builder, _scoped(filters), dateField, dateOp);
      final dynamic rows = await builder;
      num total = 0;
      for (final dynamic row in SafeJson.asList(rows)) {
        if (row is Map) total += SafeJson.asMoney(row[column]);
      }
      return total;
    } catch (e) {
      AppLogger.warning('DASHBOARD', 'sum($table.$column) failed', error: e);
      return 0;
    }
  }

  Future<List<dynamic>> _recentSales() async {
    try {
      dynamic builder = supabase
          .table('sales')
          .select(
            'id, sale_number, sale_date, total_amount, paid_amount, status, '
            'customer:customers(name)',
          )
          .order('created_at', ascending: false)
          .limit(8);
      if (activeShowroomId.isNotEmpty) {
        builder = builder.eq('showroom_id', activeShowroomId);
      }
      return SafeJson.asList(await builder);
    } catch (e) {
      AppLogger.warning('DASHBOARD', 'recent sales failed', error: e);
      return <dynamic>[];
    }
  }

  dynamic _applyFilters(
    dynamic builder,
    Map<String, String> filters,
    String? dateField,
    _DateOp dateOp,
  ) {
    for (final MapEntry<String, String> entry in filters.entries) {
      if (entry.key == dateField) {
        switch (dateOp) {
          case _DateOp.eq:
            builder = builder.eq(entry.key, entry.value);
          case _DateOp.gte:
            builder = builder.gte(entry.key, entry.value);
          case _DateOp.lte:
            builder = builder.lte(entry.key, entry.value);
        }
        continue;
      }
      builder = builder.eq(entry.key, entry.value);
    }
    return builder;
  }

  static String _day(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

/// Comparison applied to the date filter of a KPI query.
enum _DateOp { eq, gte, lte }
