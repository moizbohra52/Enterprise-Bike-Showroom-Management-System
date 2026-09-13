import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/purchases/models/purchase_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for suppliers and purchases.
///
/// Supplier mutations are normal table ops (offline-queueable); purchase
/// creation and goods-receipt are the transactional RPC
/// `create_purchase_transaction` / `receive_purchase`.
class PurchaseRepository {
  PurchaseRepository(this.supabase);

  final SupabaseService supabase;

  // ------------------------------------------------------------- suppliers

  Future<PaginatedResponse<SupplierModel>> listSuppliers(PageQuery query) async {
    try {
      var builder = supabase
          .table('suppliers')
          .select('*', count: CountOption.exact)
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'name.ilike.%$term%,phone.ilike.%$term%,city.ilike.%$term%,gstin.ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      builder = builder.order('name', ascending: true);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<SupplierModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => SupplierModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<SupplierModel?> supplierById(String id) async {
    try {
      final dynamic row = await supabase
          .table('suppliers')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return SupplierModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<SupplierModel> createSupplier(Map<String, dynamic> payload) async {
    try {
      final dynamic row = await supabase
          .table('suppliers')
          .insert(payload)
          .select()
          .single();
      return SupplierModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<SupplierModel> updateSupplier(
      String id, Map<String, dynamic> patch) async {
    try {
      final dynamic row = await supabase
          .table('suppliers')
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return SupplierModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Active suppliers for the purchase form picker.
  Future<List<Map<String, dynamic>>> activeSuppliers() async {
    try {
      final dynamic rows = await supabase
          .table('suppliers')
          .select('id, name, phone')
          .eq('status', 'active')
          .order('name')
          .limit(200);
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<void> deactivateSupplier(String id) async {
    try {
      await supabase
          .table('suppliers')
          .update(<String, dynamic>{
            'status': 'inactive',
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ------------------------------------------------------------- purchases

  Future<PaginatedResponse<PurchaseModel>> list(PageQuery query) async {
    try {
      var builder = supabase
          .table('purchases')
          .select(
            '*, supplier:suppliers(name, phone)',
            count: CountOption.exact,
          )
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'purchase_number.ilike.%$term%,supplier:suppliers(name).ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      final String? supplierId =
          SafeJson.asString(query.filters['supplier_id']);
      if (supplierId != null && supplierId.isNotEmpty) {
        builder = builder.eq('supplier_id', supplierId);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<PurchaseModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => PurchaseModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<PurchaseModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('purchases')
          .select('*, supplier:suppliers(name, phone), purchase_items(*)')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return PurchaseModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Creates a purchase order (transactional RPC: purchase + ledger).
  Future<PurchaseModel> create({
    required String supplierId,
    required String showroomId,
    required List<Map<String, dynamic>> lines,
    DateTime? orderDate,
    DateTime? expectedDate,
    num discount = 0,
    num taxRate = 0,
    String? notes,
  }) async {
    try {
      final dynamic row = await supabase.rpc(
          'create_purchase_transaction',
          params: <String, dynamic>{
            'supplier_id': supplierId,
            'showroom_id': showroomId,
            'order_date':
                (orderDate ?? DateTime.now()).toIso8601String(),
            'expected_date': expectedDate?.toIso8601String(),
            'discount_amount': discount,
            'tax_rate': taxRate,
            'notes': notes,
            'lines': lines,
          });
      if (row is! Map) {
        throw AppException('create_purchase_transaction returned no row.');
      }
      return PurchaseModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Marks goods as received (creates/updates inventory stock, updates
  /// accounting) — transactional RPC.
  Future<void> receive(String purchaseId,
      {Map<String, dynamic>? chassisByLine}) async {
    try {
      await supabase.rpc('receive_purchase', params: <String, dynamic>{
        'p_purchase_id': purchaseId,
        'p_received_date': DateTime.now().toIso8601String(),
        if (chassisByLine != null) 'p_chassis_numbers': chassisByLine,
      });
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Pays a supplier against a purchase (ledger entry).
  Future<void> pay({
    required String purchaseId,
    required num amount,
    required String paymentMode,
    String? referenceNumber,
  }) async {
    try {
      await supabase.rpc('pay_supplier', params: <String, dynamic>{
        'p_purchase_id': purchaseId,
        'p_amount': amount,
        'p_payment_mode': paymentMode,
        'p_payment_date': DateTime.now().toIso8601String(),
        'p_reference_number': referenceNumber,
      });
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Marker for RPC-level failures.
typedef PurchaseFlowException = AppException;
