import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/billing/models/invoice_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for invoices.
///
/// Invoices are created by the `create_invoice` RPC (called from
/// [SaleRepository.completeSale]); the UI may void or re-issue them.
class InvoiceRepository {
  InvoiceRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<InvoiceModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('invoices')
          .select('*, customer:customers(name, phone)');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'invoice_number.ilike.%$term%,customer:customers(name).ilike.%$term%',
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
      if (from != null && from.isNotEmpty) {
        builder = builder.gte('invoice_date', from);
      }
      if (to != null && to.isNotEmpty) builder = builder.lte('invoice_date', to);
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<InvoiceModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => InvoiceModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<InvoiceModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('invoices')
          .select('*, customer:customers(name, phone, address, city, pincode), sale_items(*), invoice_items(*)')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return InvoiceModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Voids an invoice (allowed only when nothing has been paid against it).
  Future<void> voidInvoice(String id, String reason) async {
    try {
      await supabase
          .table('invoices')
          .update(<String, dynamic>{
            'status': 'void',
            'void_reason': reason,
            'voided_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('paid_amount', 0);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Payments received against an invoice.
  Future<List<Map<String, dynamic>>> paymentsFor(String invoiceId) async {
    try {
      final dynamic rows = await supabase
          .table('payments')
          .select()
          .eq('invoice_id', invoiceId)
          .order('created_at');
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Receives a payment against an invoice via the transactional RPC.
  Future<Map<String, dynamic>> recordPayment({
    required String invoiceId,
    required num amount,
    required String paymentMode,
    required String? customerId,
    String? referenceNumber,
    DateTime? paymentDate,
    String? notes,
  }) async {
    try {
      final dynamic row = await supabase.rpc('record_payment', params: <String, dynamic>{
        'p_invoice_id': invoiceId,
        'p_amount': amount,
        'p_payment_mode': paymentMode,
        'p_payment_date':
            (paymentDate ?? DateTime.now()).toIso8601String(),
        'p_customer_id': customerId,
        'p_reference_number': referenceNumber,
        'p_notes': notes,
      });
      if (row is Map) return SafeJson.asMap(row);
      return <String, dynamic>{'id': row?.toString()};
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Refunds a payment (voids it; the invoice balance increases).
  Future<Map<String, dynamic>> refundPayment({
    required String paymentId,
    required String reason,
    String? referenceNumber,
  }) async {
    try {
      final dynamic row = await supabase.rpc('refund_payment', params: <String, dynamic>{
        'p_payment_id': paymentId,
        'p_reason': reason,
        'p_reference_number': referenceNumber,
      });
      if (row is Map) return SafeJson.asMap(row);
      return <String, dynamic>{'id': row?.toString()};
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Marker for downstream-step failures (kept local to billing).
typedef InvoiceFlowException = AppException;
