import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/date_utils.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

/// One aggregate result (row count + summed amount).
class DashboardMetric {
  const DashboardMetric({this.count = 0, this.total = 0});

  final int count;
  final num total;

  static const DashboardMetric empty = DashboardMetric();

  bool get isEmpty => count == 0 && total == 0;
}

/// A single month in the sales trend series.
class DashboardTrendPoint {
  const DashboardTrendPoint({required this.label, required this.amount});

  final String label;
  final num amount;
}

/// Everything the dashboard renders, loaded as one snapshot.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.generatedAt,
    required this.todaySales,
    required this.monthSales,
    required this.prevMonthSales,
    required this.todayCollections,
    required this.monthExpenses,
    required this.pendingExpenses,
    required this.receivables,
    required this.overdueEmis,
    required this.openJobs,
    required this.stockAvailable,
    required this.stockReserved,
    required this.upcomingReminders,
    required this.recentSales,
    required this.trend,
  });

  final DateTime generatedAt;

  /// Completed sales today.
  final DashboardMetric todaySales;

  /// Completed sales in the current and previous month.
  final DashboardMetric monthSales;
  final DashboardMetric prevMonthSales;

  /// Payments received today.
  final DashboardMetric todayCollections;
  final DashboardMetric monthExpenses;

  /// Expenses awaiting approval.
  final DashboardMetric pendingExpenses;

  /// Outstanding invoice balance.
  final DashboardMetric receivables;

  /// EMIs that are due or overdue.
  final DashboardMetric overdueEmis;

  /// Job cards that are not delivered/cancelled yet.
  final DashboardMetric openJobs;

  /// Unit stock by inventory status.
  final int stockAvailable;
  final int stockReserved;

  /// Reminders due in the next 7 days (raw rows).
  final List<Map<String, dynamic>> upcomingReminders;

  /// Latest sales (raw rows, already scoped to the showroom).
  final List<Map<String, dynamic>> recentSales;

  /// Monthly revenue trend (oldest first).
  final List<DashboardTrendPoint> trend;

  /// Revenue change versus the previous month (percent, may be negative).
  num get monthOverMonthChange {
    if (prevMonthSales.total == 0) return monthSales.total == 0 ? 0 : 100;
    return ((monthSales.total - prevMonthSales.total) /
            prevMonthSales.total) *
        100;
  }

  /// True when every metric came back empty (fresh install or no access).
  bool get isBlank {
    return todaySales.isEmpty &&
        monthSales.isEmpty &&
        receivables.isEmpty &&
        openJobs.isEmpty &&
        stockAvailable == 0 &&
        recentSales.isEmpty;
  }
}

/// Read-only aggregate queries for the dashboard.
///
/// Aggregation is done client-side over capped result sets; a `dashboard_*`
/// Postgres function can replace this without touching the UI (see
/// docs/ROADMAP.md). Each query degrades to zero on failure so a missing table
/// or RLS policy never blanks the whole dashboard.
class DashboardRepository {
  DashboardRepository(this.supabase);

  final SupabaseService supabase;

  /// Max rows pulled for a single client-side aggregate.
  static const int _scanLimit = 1000;

  Future<DashboardSnapshot> load({
    String? showroomId,
    int trendMonths = 6,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateUtils.startOfDay(now);
    final DateTime monthStart = DateUtils.startOfMonth(now);
    final DateTime prevStart = DateUtils.addMonths(monthStart, -1);
    final DateTime trendStart =
        DateUtils.addMonths(monthStart, -(trendMonths - 1));

    final List<Future<dynamic>> queries = <Future<dynamic>>[
      _metric(
        'sales',
        amountColumn: 'total_amount',
        eq: <String, dynamic>{'status': 'completed'},
        gte: today,
        dateColumn: 'sale_date',
        showroomId: showroomId,
      ),
      _metric(
        'sales',
        amountColumn: 'total_amount',
        eq: <String, dynamic>{'status': 'completed'},
        gte: monthStart,
        dateColumn: 'sale_date',
        showroomId: showroomId,
      ),
      _metric(
        'sales',
        amountColumn: 'total_amount',
        eq: <String, dynamic>{'status': 'completed'},
        gte: prevStart,
        lt: monthStart,
        dateColumn: 'sale_date',
        showroomId: showroomId,
      ),
      _metric(
        'payments',
        amountColumn: 'amount',
        eq: <String, dynamic>{'status': 'completed'},
        gte: today,
        dateColumn: 'payment_date',
        showroomId: showroomId,
      ),
      _metric(
        'expenses',
        amountColumn: 'amount',
        gte: monthStart,
        dateColumn: 'date',
        showroomId: showroomId,
      ),
      _metric(
        'expenses',
        eq: <String, dynamic>{'status': 'pending'},
        gte: monthStart,
        dateColumn: 'date',
        showroomId: showroomId,
      ),
      _metric(
        'invoices',
        amountColumn: 'outstanding_amount',
        inFilter: <String, List<String>>{
          'status': <String>['finalized', 'partially_paid', 'overdue'],
        },
        showroomId: showroomId,
      ),
      _metric(
        'emi_schedules',
        amountColumn: 'emi_amount',
        inFilter: <String, List<String>>{
          'status': <String>['due', 'overdue'],
        },
        showroomId: showroomId,
      ),
      _metric(
        'service_records',
        inFilter: <String, List<String>>{
          'status': <String>[
            'booked',
            'received',
            'in_progress',
            'waiting_for_parts',
          ],
        },
        showroomId: showroomId,
      ),
      _count(
        'inventory',
        eq: <String, dynamic>{'status': 'available'},
        showroomId: showroomId,
      ),
      _count(
        'inventory',
        eq: <String, dynamic>{'status': 'reserved'},
        showroomId: showroomId,
      ),
      _rows(
        'reminders',
        columns: 'id,title,reminder_date,type',
        gte: today,
        lte: DateUtils.addDays(today, 7),
        dateColumn: 'reminder_date',
        extraEq: <String, dynamic>{'status': 'pending'},
        showroomId: showroomId,
        limit: 8,
        order: 'reminder_date',
      ),
      _rows(
        'sales',
        columns:
            'id,sale_number,sale_date,total_amount,status,customer:customers(name)',
        showroomId: showroomId,
        limit: 8,
        order: 'sale_date',
        ascending: false,
      ),
      _rows(
        'sales',
        columns: 'sale_date,total_amount',
        gte: trendStart,
        dateColumn: 'sale_date',
        showroomId: showroomId,
        limit: _scanLimit,
        order: 'sale_date',
        ascending: false,
      ),
    ];

    final List<dynamic> r = await Future.wait(queries);

    return DashboardSnapshot(
      generatedAt: now,
      todaySales: _metricOf(r[0]),
      monthSales: _metricOf(r[1]),
      prevMonthSales: _metricOf(r[2]),
      todayCollections: _metricOf(r[3]),
      monthExpenses: _metricOf(r[4]),
      pendingExpenses: _metricOf(r[5]),
      receivables: _metricOf(r[6]),
      overdueEmis: _metricOf(r[7]),
      openJobs: _metricOf(r[8]),
      stockAvailable: r[9] is int ? r[9] as int : 0,
      stockReserved: r[10] is int ? r[10] as int : 0,
      upcomingReminders: _maps(r[11]),
      recentSales: _maps(r[12]),
      trend: _foldTrend(r[13], months: trendMonths, monthStart: monthStart),
    );
  }

  // ------------------------------------------------------------------ helpers

  DashboardMetric _metricOf(dynamic value) =>
      value is DashboardMetric ? value : DashboardMetric.empty;

  List<Map<String, dynamic>> _maps(dynamic value) {
    return <Map<String, dynamic>>[
      for (final dynamic row in SafeJson.asList(value))
        if (row is Map) SafeJson.asMap(row),
    ];
  }

  /// Count + optional column sum for one filtered table.
  Future<DashboardMetric> _metric(
    String table, {
    String? amountColumn,
    Map<String, dynamic> eq = const <String, dynamic>{},
    Map<String, List<String>> inFilter = const <String, List<String>>{},
    DateTime? gte,
    DateTime? lt,
    String dateColumn = 'created_at',
    String? showroomId,
  }) async {
    try {
      dynamic builder = supabase.client.from(table).select(
            amountColumn == null ? 'id' : amountColumn,
            count: CountOption.exact,
          );
      for (final MapEntry<String, dynamic> e in eq.entries) {
        builder = builder.eq(e.key, e.value);
      }
      for (final MapEntry<String, List<String>> e in inFilter.entries) {
        builder = builder.in_(e.key, e.value);
      }
      if (showroomId != null) builder = builder.eq('showroom_id', showroomId);
      if (gte != null) builder = builder.gte(dateColumn, DateUtils.isoDate(gte));
      if (lt != null) builder = builder.lt(dateColumn, DateUtils.isoDate(lt));
      builder = builder.range(0, _scanLimit - 1);
      final dynamic result = await builder;
      final int count = SafeJson.asIntOr(_countOf(result), 0);
      num total = 0;
      if (amountColumn != null) {
        for (final dynamic row in SafeJson.asList(result)) {
          if (row is! Map) continue;
          total += SafeJson.asMoney(SafeJson.asMap(row)[amountColumn]);
        }
      }
      return DashboardMetric(count: count, total: total);
    } catch (e) {
      AppLogger.warning('DASHBOARD', 'metric failed for $table', error: e);
      return DashboardMetric.empty;
    }
  }

  Future<int> _count(
    String table, {
    Map<String, dynamic> eq = const <String, dynamic>{},
    String? showroomId,
  }) async {
    try {
      dynamic builder =
          supabase.client.from(table).select('id', count: CountOption.exact);
      for (final MapEntry<String, dynamic> e in eq.entries) {
        builder = builder.eq(e.key, e.value);
      }
      if (showroomId != null) builder = builder.eq('showroom_id', showroomId);
      final dynamic result = await builder;
      return SafeJson.asIntOr(_countOf(result), 0);
    } catch (e) {
      AppLogger.warning('DASHBOARD', 'count failed for $table', error: e);
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _rows(
    String table, {
    required String columns,
    Map<String, dynamic> extraEq = const <String, dynamic>{},
    DateTime? gte,
    DateTime? lte,
    String dateColumn = 'created_at',
    String? showroomId,
    int limit = 20,
    String? order,
    bool ascending = true,
  }) async {
    try {
      dynamic builder = supabase.client.from(table).select(columns);
      for (final MapEntry<String, dynamic> e in extraEq.entries) {
        builder = builder.eq(e.key, e.value);
      }
      if (showroomId != null) builder = builder.eq('showroom_id', showroomId);
      if (gte != null) builder = builder.gte(dateColumn, DateUtils.isoDate(gte));
      if (lte != null) builder = builder.lte(dateColumn, DateUtils.isoDate(lte));
      if (order != null) builder = builder.order(order, ascending: ascending);
      builder = builder.limit(limit);
      return _maps(await builder);
    } catch (e) {
      AppLogger.warning('DASHBOARD', 'rows failed for $table', error: e);
      return const <Map<String, dynamic>>[];
    }
  }

  dynamic _countOf(dynamic result) {
    try {
      // ignore: avoid_dynamic_calls
      return result.count;
    } catch (_) {
      return null;
    }
  }

  /// Buckets raw `{sale_date, total_amount}` rows into monthly totals.
  List<DashboardTrendPoint> _foldTrend(
    dynamic value, {
    required int months,
    required DateTime monthStart,
  }) {
    final Map<String, num> byMonth = <String, num>{};
    for (final dynamic row in SafeJson.asList(value)) {
      if (row is! Map) continue;
      final Map<String, dynamic> json = SafeJson.asMap(row);
      final DateTime? date = SafeJson.asDay(json['sale_date']);
      if (date == null) continue;
      final String key = DateUtils.isoMonth(date);
      if (key.isEmpty) continue;
      byMonth[key] = (byMonth[key] ?? 0) + SafeJson.asMoney(json['total_amount']);
    }
    final List<DashboardTrendPoint> points = <DashboardTrendPoint>[];
    for (int i = months - 1; i >= 0; i--) {
      final DateTime month = DateUtils.addMonths(monthStart, -i);
      final String key = DateUtils.isoMonth(month);
      points.add(
        DashboardTrendPoint(
          label: DateUtils.monthLabel(month),
          amount: byMonth[key] ?? 0,
        ),
      );
    }
    return points;
  }
}
