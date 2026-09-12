import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/reports/models/report_definition.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// The report catalog. Sources are SQL views / RPCs (migration 011/012).
class ReportCatalog {
  ReportCatalog._();

  static const List<ReportDefinition> all = <ReportDefinition>[
    ReportDefinition(
      key: 'daily_sales',
      title: 'Daily Sales',
      description: 'Sales per day for a date range.',
      source: 'daily_sales_summary',
      columns: const <String>[
        'sale_date',
        'showroom_name',
        'sales_count',
        'total_amount',
        'paid_amount',
        'balance_amount',
      ],
    ),
    ReportDefinition(
      key: 'monthly_sales',
      title: 'Monthly Sales',
      description: 'Sales trend by month.',
      source: 'monthly_sales_summary',
      columns: const <String>[
        'month',
        'showroom_name',
        'sales_count',
        'total_amount',
      ],
    ),
    ReportDefinition(
      key: 'profit',
      title: 'Showroom Profit',
      description: 'Revenue, cost and profit per showroom.',
      source: 'showroom_profit_summary',
      columns: const <String>[
        'showroom_name',
        'revenue',
        'cost_of_goods',
        'expenses',
        'profit',
      ],
    ),
    ReportDefinition(
      key: 'customer_outstanding',
      title: 'Customer Outstanding',
      description: 'Open balances owed per customer.',
      source: 'customer_outstanding_summary',
      columns: const <String>[
        'customer_name',
        'phone',
        'outstanding_amount',
        'open_invoices',
      ],
    ),
    ReportDefinition(
      key: 'emi_due',
      title: 'EMI Due',
      description: 'EMIs due in the next 30 days.',
      source: 'emi_due_summary',
      columns: const <String>[
        'customer_name',
        'loan_number',
        'installment_no',
        'due_date',
        'emi_amount',
      ],
    ),
    ReportDefinition(
      key: 'emi_overdue',
      title: 'EMI Overdue',
      description: 'Overdue EMI installments.',
      source: 'emi_overdue_summary',
      columns: const <String>[
        'customer_name',
        'loan_number',
        'installment_no',
        'due_date',
        'emi_amount',
        'days_overdue',
      ],
    ),
    ReportDefinition(
      key: 'service_revenue',
      title: 'Service Revenue',
      description: 'Workshop revenue by job type and period.',
      source: 'service_revenue_summary',
      columns: const <String>[
        'period',
        'job_type',
        'job_count',
        'total_amount',
      ],
    ),
    ReportDefinition(
      key: 'inventory',
      title: 'Inventory Summary',
      description: 'Stock counts by product and status.',
      source: 'inventory_summary',
      columns: const <String>[
        'product_name',
        'status',
        'showroom_name',
        'quantity',
        'stock_value',
      ],
    ),
    ReportDefinition(
      key: 'stock_valuation',
      title: 'Stock Valuation',
      description: 'Valuation of available stock at cost.',
      source: 'stock_valuation_view',
      columns: const <String>[
        'showroom_name',
        'total_units',
        'total_value',
      ],
    ),
    ReportDefinition(
      key: 'purchase',
      title: 'Purchases',
      description: 'Purchases by supplier and status.',
      source: 'purchase_summary',
      columns: const <String>[
        'supplier_name',
        'order_date',
        'status',
        'total_amount',
        'paid_amount',
        'outstanding_amount',
      ],
    ),
    ReportDefinition(
      key: 'expense',
      title: 'Expenses',
      description: 'Expenses by category and period.',
      source: 'expense_summary',
      columns: const <String>[
        'period',
        'category_name',
        'expense_count',
        'total_amount',
      ],
    ),
    ReportDefinition(
      key: 'pnl',
      title: 'Profit & Loss',
      description: 'P&L statement by account group.',
      source: 'pnl_view',
      columns: const <String>[
        'account_type',
        'account_name',
        'amount',
      ],
    ),
  ];

  static ReportDefinition? byKey(String key) {
    for (final ReportDefinition r in all) {
      if (r.key == key) return r;
    }
    return null;
  }
}

/// Fetches report rows from the backing SQL view / RPC.
class ReportRepository {
  ReportRepository(this.supabase);

  final SupabaseService supabase;

  /// Runs a report and returns raw rows (capped for the UI).
  Future<List<Map<String, dynamic>>> run(
    ReportDefinition definition, {
    Map<String, dynamic>? params,
    int limit = 1000,
  }) async {
    try {
      // Views are queried with a range; RPC reports pass params.
      final dynamic rows;
      final Map<String, dynamic> safeParams =
          params ?? const <String, dynamic>{};
      if (definition.source.endsWith('_view') ||
          definition.source.endsWith('_summary')) {
        var builder = supabase
            .table(definition.source)
            .select('*')
            .limit(limit);
        final String? showroomId =
            SafeJson.asString(safeParams['showroom_id']);
        if (showroomId != null && showroomId.isNotEmpty) {
          builder = builder.eq('showroom_id', showroomId);
        }
        rows = await builder;
      } else {
        rows = await supabase.rpc(
            definition.source,
            <String, dynamic>{...(params ?? const <String, dynamic>{})});
      }
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Marker for report-level failures.
typedef ReportFlowException = AppException;
