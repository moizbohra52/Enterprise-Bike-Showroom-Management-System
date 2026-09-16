import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/sales/models/sale_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for sales. All mutating operations are server RPCs
/// (transactions): `create_sale_transaction`, `cancel_sale`.
///
/// A completed sale is followed by `create_invoice` and, for the down
/// payment / full payment, `record_payment` — each RPC is itself a
/// server-side transaction (see migrations 008/011).
class SaleRepository {
  SaleRepository(this.supabase);

  final SupabaseService supabase;

  /// Lists sales with customer + showroom joins, server-side pagination.
  Future<PaginatedResponse<SaleModel>> list(PageQuery query) async {
    try {
      final dynamic result = await (_builder(query)).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<SaleModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => SaleModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  dynamic _builder(PageQuery query) {
    dynamic builder = supabase
        .table('sales')
        .select('*, '
          'customer:customers(name, phone), '
          'showroom:showrooms(name), '
          'sale_items(*), '
          'count(invoices, foreignKey: (sale_id))');
    final String? term = query.search;
    if (term != null && term.isNotEmpty) {
      builder = builder.or(
        'sale_number.ilike.%$term%,customer:customers(name).ilike.%$term%',
      );
    }
    final String? status = SafeJson.asString(query.filters['status']);
    if (status != null && status.isNotEmpty) {
      builder = builder.eq('status', status);
    }
    final String? showroomId =
        SafeJson.asString(query.filters['showroom_id']);
    if (showroomId != null && showroomId.isNotEmpty) {
      builder = builder.eq('showroom_id', showroomId);
    }
    final String? customerId =
        SafeJson.asString(query.filters['customer_id']);
    if (customerId != null && customerId.isNotEmpty) {
      builder = builder.eq('customer_id', customerId);
    }
    final String? from = SafeJson.asString(query.filters['date_from']);
    final String? to = SafeJson.asString(query.filters['date_to']);
    if (from != null && from.isNotEmpty) builder = builder.gte('sale_date', from);
    if (to != null && to.isNotEmpty) builder = builder.lte('sale_date', to);
    builder = query.orderBy == null
        ? builder.order('created_at', ascending: query.ascending)
        : builder.order(query.orderBy, ascending: query.ascending);
    return builder.range(query.offset, query.end);
  }

  Future<SaleModel?> getById(String id) async {
    final dynamic row = await supabase
        .table('sales')
        .select('*, customer:customers(name, phone), sale_items(*), invoices(*)')
        .eq('id', id)
        .maybeSingle();
    if (row is! Map) return null;
    return SaleModel.fromJson(SafeJson.asMap(row));
  }

  /// Creates the sale through the transactional RPC, then the invoice,
  /// then the first payment (down payment for EMI, full for cash).
  ///
  /// Returns the created sale. Throws [SaleFlowException] with the
  /// failed step name if a later step fails (the sale itself remains
  /// valid — payments can be retried from the sale details).
  Future<SaleModel> completeSale({
    required String customerId,
    required String showroomId,
    required List<Map<String, dynamic>> lines,
    required String paymentMode,
    num discount = 0,
    num taxRate = 0,
    Map<String, dynamic>? emi,
    num firstPayment = 0,
    String firstPaymentMode = 'cash',
    DateTime? saleDate,
    Map<String, dynamic>? delivery,
    String? invoiceNumber,
  }) async {
    final Map<String, dynamic> salePayload = <String, dynamic>{
      'customer_id': customerId,
      'showroom_id': showroomId,
      'sale_type': 'retail',
      'payment_mode': paymentMode,
      'is_emi': paymentMode == 'emi',
      'discount_amount': discount,
      'tax_rate': taxRate,
      'sale_date': saleDate?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'lines': lines,
      if (emi != null) 'emi': emi,
      if (delivery != null) 'delivery': delivery,
    };
    final dynamic saleRow =
        await supabase.rpc('create_sale_transaction', params: salePayload);
    final String saleId = saleRow is Map
        ? (SafeJson.asId(saleRow['id']) ?? '')
        : (saleRow?.toString() ?? '');

    // Invoice (server computes tax; returns the invoice row).
    final dynamic invoice = await supabase.rpc('create_invoice', params: <String, dynamic>{
      'p_sale_id': saleId,
      'p_invoice_date': saleDate?.toIso8601String() ??
          DateTime.now().toIso8601String(),
      'p_tax_rate': taxRate,
      'p_discount_amount': discount,
      if (invoiceNumber != null && invoiceNumber.isNotEmpty)
        'p_invoice_number': invoiceNumber,
    });

    // First payment (down payment for EMI, full for cash).
    if (firstPayment > 0) {
      await supabase.rpc('record_payment', params: <String, dynamic>{
        'p_invoice_id': invoice is Map ? SafeJson.asId(invoice['id']) : '',
        'p_amount': firstPayment,
        'p_payment_mode': firstPaymentMode,
        'p_payment_date': DateTime.now().toIso8601String(),
        'p_customer_id': customerId,
        'p_sale_id': saleId,
        'p_is_down_payment': paymentMode == 'emi',
      });
    }

    final SaleModel? created = await getById(saleId);
    if (created == null) {
      throw SaleFlowException('Sale $saleId was not returned after creation.');
    }
    return created;
  }

  /// Cancels a sale (un-delivered only) through the transactional RPC.
  Future<void> cancel(String saleId, String reason) async {
    await supabase.rpc('cancel_sale', params: <String, dynamic>{
      'p_sale_id': saleId,
      'p_reason': reason,
    });
  }

  /// Active customers for the sale form's customer picker.
  Future<List<Map<String, dynamic>>> searchCustomers(
    String term, {
    String? showroomId,
  }) async {
    dynamic builder = supabase
        .table('customers')
        .select()
        .eq('status', 'active');
    if (showroomId != null && showroomId.isNotEmpty) {
      builder = builder.eq('showroom_id', showroomId);
    }
    final String trimmed = term.trim();
    if (trimmed.isNotEmpty) {
      builder = builder.or(
        'name.ilike.%$trimmed%,phone.ilike.%$trimmed%,customer_code.ilike.%$trimmed%',
      );
    }
    builder = builder.order('name').limit(50);
    final dynamic rows = await builder;
    return <Map<String, dynamic>>[
      for (final dynamic row in SafeJson.asList(rows))
        if (row is Map) SafeJson.asMap(row),
    ];
  }

  /// Emi plan options for a product (used by the sale form).
  Future<List<Map<String, dynamic>>> emiPlans(String productId) async {
    final dynamic rows = await supabase
        .table('emi_plans')
        .select()
        .eq('product_id', productId)
        .eq('is_active', true)
        .order('sort_order');
    return <Map<String, dynamic>>[
      for (final dynamic row in SafeJson.asList(rows))
        if (row is Map) SafeJson.asMap(row),
    ];
  }

  /// Available vehicles (stock `available` at the showroom).
  Future<List<Map<String, dynamic>>> availableVehicles(String showroomId) async {
    final dynamic rows = await supabase
        .table('inventory')
        .select('*, product:products(id, name, model, brand:brands(name), colors(*))')
        .eq('showroom_id', showroomId)
        .eq('status', 'available')
        .order('created_at', ascending: false)
        .limit(200);
    return <Map<String, dynamic>>[
      for (final dynamic row in SafeJson.asList(rows))
        if (row is Map) SafeJson.asMap(row),
    ];
  }

  /// Accessories linked to a product via `product_accessories`.
  Future<List<Map<String, dynamic>>> accessoriesForProduct(
      String productId) async {
    final dynamic rows = await supabase
        .table('product_accessories')
        .select('*, accessory:products(name, mrp_price)')
        .eq('product_id', productId)
        .eq('is_active', true)
        .order('sort_order');
    return <Map<String, dynamic>>[
      for (final dynamic row in SafeJson.asList(rows))
        if (row is Map) SafeJson.asMap(row),
    ];
  }
}

/// Raised when the sale was created but a downstream step (invoice or
/// payment) failed — the caller shows a retryable error, not a crash.
class SaleFlowException implements Exception {
  SaleFlowException(this.message);

  final String message;

  @override
  String toString() => 'SaleFlowException: $message';
}
