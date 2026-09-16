import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/customers/models/customer_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/local_database_service.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for customers and customer vehicles.
///
/// Offline: create/update/delete are queued; the read-through cache keeps
/// lists usable without connectivity.
class CustomerRepository {
  CustomerRepository(this.supabase, this.local);

  final SupabaseService supabase;

  /// Local cache for offline reads.
  final LocalDatabaseService local;

  static const String _table = 'customers';

  // ------------------------------------------------------------------ list

  Future<PaginatedResponse<CustomerModel>> list(PageQuery query) async {
    try {
      // `customers_with_summary` is an SQL view (migration 011) that adds
      // derived `outstanding` and `vehicle_count` columns.
      dynamic builder = supabase
          .table('customers_with_summary')
          .select('*');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'name.ilike.%$term%,phone.ilike.%$term%,email.ilike.%$term%,customer_code.ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) builder = builder.eq('status', status);
      final String? type = SafeJson.asString(query.filters['customer_type']);
      if (type != null && type.isNotEmpty) {
        builder = builder.eq('customer_type', type);
      }
      final String? showroomId =
          SafeJson.asString(query.filters['showroom_id']);
      if (showroomId != null && showroomId.isNotEmpty) {
        builder = builder.eq('showroom_id', showroomId);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<CustomerModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => CustomerModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<CustomerModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return CustomerModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Create (remote-first; offline handled by the caller via the sync queue).
  Future<CustomerModel> create(Map<String, dynamic> payload) async {
    try {
      final dynamic row =
          await supabase.table(_table).insert(payload).select().single();
      return CustomerModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<CustomerModel> update(String id, Map<String, dynamic> patch) async {
    try {
      final dynamic row = await supabase
          .table(_table)
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return CustomerModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<void> softDelete(String id) async {
    try {
      await supabase.table(_table).update(<String, dynamic>{
        'status': 'inactive',
        'is_deleted': true,
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // -------------------------------------------------------------- vehicles

  Future<List<CustomerVehicleModel>> vehicles(String customerId) async {
    try {
      final dynamic rows = await supabase
          .table('customer_vehicles')
          .select('*, product:products(name, model, brand:brands(name))')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return <CustomerVehicleModel>[
        for (final dynamic r in SafeJson.asList(rows));
          if (r is Map) CustomerVehicleModel.fromJson(SafeJson.asMap(r)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<void> updateVehicle(String id, Map<String, dynamic> patch) async {
    try {
      await supabase.table('customer_vehicles').update(patch).eq('id', id);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<CustomerVehicleModel?> vehicleById(String id) async {
    try {
      final dynamic row = await supabase
          .table('customer_vehicles')
          .select('*, product:products(name, model, brand:brands(name))')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return CustomerVehicleModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ------------------------------------------------- customer 360 (tabs)

  /// Generic joined read used by the Customer 360 tabs.
  Future<List<Map<String, dynamic>>> relatedRows(
    String table, {
    required String column,
    required String customerId,
    String? order,
    int limit = 100,
  }) async {
    dynamic builder = supabase.table(table).select().eq(column, customerId).limit(limit);
    if (order != null) {
      builder = builder.order(order, ascending: false);
    }
    final dynamic rows = await builder;
    return <Map<String, dynamic>>[
      for (final dynamic r in SafeJson.asList(rows));
        if (r is Map) SafeJson.asMap(r),
    ];
  }

  /// Timeline events across sales, invoices, payments, loans, services,
  /// warranties and insurance (built from joined rows).
  Future<List<Map<String, dynamic>>> timeline(String customerId) async {
    final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];

    Future<void> _add(String type, String label, String? date, String? amount) async {
      events.add(<String, dynamic>{
        'type': type,
        'label': label,
        'date': date,
        'amount': amount,
      });
    }

    final List<Map<String, dynamic>> sales =
        await relatedRows('sales', column: 'customer_id', customerId: customerId);
    for (final Map<String, dynamic> s in sales) {
      await _add(
        'sale',
        'Sale ${SafeJson.asText(s['sale_number'])}',
        SafeJson.asString(s['sale_date']),
        SafeJson.asMoney(s['total_amount']).toString(),
      );
    }
    final List<Map<String, dynamic>> invoices =
        await relatedRows('invoices', column: 'customer_id', customerId: customerId);
    for (final Map<String, dynamic> i in invoices) {
      await _add(
        'invoice',
        'Invoice ${SafeJson.asText(i['invoice_number'])}',
        SafeJson.asString(i['invoice_date']),
        SafeJson.asMoney(i['total_amount']).toString(),
      );
    }
    final List<Map<String, dynamic>> payments =
        await relatedRows('payments', column: 'customer_id', customerId: customerId);
    for (final Map<String, dynamic> p in payments) {
      await _add(
        'payment',
        'Payment ${SafeJson.asText(p['payment_number'])}',
        SafeJson.asString(p['payment_date']),
        SafeJson.asMoney(p['amount']).toString(),
      );
    }
    final List<Map<String, dynamic>> loans = await relatedRows(
        'loans',
        column: 'customer_id',
        customerId: customerId);
    for (final Map<String, dynamic> l in loans) {
      await _add(
        'loan',
        'Loan ${SafeJson.asText(l['loan_number'])}',
        SafeJson.asString(l['start_date']),
        SafeJson.asMoney(l['loan_amount']).toString(),
      );
    }

    // Service events come via the customer's vehicles.
    final List<CustomerVehicleModel> vehicleList = await this.vehicles(customerId);
    for (final CustomerVehicleModel v in vehicleList) {
      if (v.id == null) continue;
      final List<Map<String, dynamic>> services = await relatedRows(
          'service_records',
          column: 'vehicle_id',
          customerId: v.id!);
      for (final Map<String, dynamic> s in services) {
        await _add(
          'service',
          'Service ${SafeJson.asText(s['service_number'])}',
          SafeJson.asString(s['service_date']),
          SafeJson.asMoney(s['total_amount']).toString(),
        );
      }
    }

    events.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final DateTime? da = DateTime.tryParse(SafeJson.asText(a['date']));
      final DateTime? db = DateTime.tryParse(SafeJson.asText(b['date']));
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return events;
  }

  /// Outstanding amount for a customer (sum of open invoices).
  Future<num> outstanding(String customerId) async {
    final List<Map<String, dynamic>> rows = await relatedRows(
      'invoices',
      column: 'customer_id',
      customerId: customerId,
    );
    num total = 0;
    for (final Map<String, dynamic> row in rows) {
      final String status = SafeJson.asText(row['status']);
      if (status == 'cancelled' || status == 'reversed' || status == 'paid') {
        continue;
      }
      total += SafeJson.asMoney(row['outstanding_amount']);
    }
    return total;
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
                'Customer no longer exists on the server.');
          }
          return SyncOperationResult.ok(
            serverId: operation.entityId,
            serverUpdatedAt: SafeJson.asDate(
                row is Map ? SafeJson.asMap(row)['updated_at'] : null),
          );
        } catch (e) {
          return _map(e);
        }
      case SyncOperation.delete:
        try {
          await supabase.table(_table).update(<String, dynamic>{
            'status': 'inactive',
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          }).eq('id', operation.entityId);
          return SyncOperationResult.ok(serverId: operation.entityId);
        } catch (e) {
          return _map(e);
        }
      default:
        return SyncOperationResult.fail(
            'Unsupported customer operation: ${operation.operation.value}');
    }
  }

  SyncOperationResult _map(Object e) {
    final AppException mapped = ErrorMapper.map(e);
    if (mapped is ConflictException || mapped is ValidationException) {
      return SyncOperationResult.conflictWith(mapped.message);
    }
    return SyncOperationResult.fail(mapped.message);
  }

  // ------------------------------------------------------- local read cache

  /// Caches the latest list page for offline display.
  Future<void> cacheList(String queryKey, List<CustomerModel> items) async {
    await local.putCache(
      'customers:$queryKey',
      <String, dynamic>{
        'items': <dynamic>[
          for (final CustomerModel item in items) item.toJson(),
        ],
      },
      ttl: const Duration(hours: 24),
    );
  }

  /// Reads the cached list when offline (best effort).
  Future<List<CustomerModel>?> cachedList(String queryKey) async {
    final Map<String, dynamic>? cached = await local.getCache('customers:$queryKey');
    if (cached == null) return null;
    final List<dynamic> raw = SafeJson.asList(cached['items']);
    return <CustomerModel>[
      for (final dynamic row in raw)
        if (row is Map)
          CustomerModel.fromJson(SafeJson.asMap(row)),
    ];
  }
}
