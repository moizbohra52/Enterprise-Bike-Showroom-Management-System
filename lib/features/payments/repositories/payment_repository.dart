import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/payments/models/payment_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for payments. All mutations are the transactional RPCs
/// `record_payment` / `refund_payment`.
class PaymentRepository {
  PaymentRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<PaymentModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('payments')
          .select('*, customer:customers(name, phone)');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'payment_number.ilike.%$term%,reference_number.ilike.%$term%,customer:customers(name).ilike.%$term%',
        );
      }
      final String? mode = SafeJson.asString(query.filters['payment_mode']);
      if (mode != null && mode.isNotEmpty) {
        builder = builder.eq('payment_mode', mode);
      }
      final String? from = SafeJson.asString(query.filters['date_from']);
      final String? to = SafeJson.asString(query.filters['date_to']);
      if (from != null && from.isNotEmpty) {
        builder = builder.gte('payment_date', from);
      }
      if (to != null && to.isNotEmpty) builder = builder.lte('payment_date', to);
      final String? customerId =
          SafeJson.asString(query.filters['customer_id']);
      if (customerId != null && customerId.isNotEmpty) {
        builder = builder.eq('customer_id', customerId);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<PaymentModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => PaymentModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<PaymentModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('payments')
          .select('*, customer:customers(name, phone), invoices(invoice_number)')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return PaymentModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Records a payment (transactional RPC: ledger + invoice balance).
  Future<PaymentModel> recordPayment({
    required String invoiceId,
    required num amount,
    required String paymentMode,
    String? customerId,
    String? saleId,
    String? referenceNumber,
    bool isDownPayment = false,
    String? notes,
  }) async {
    try {
      final dynamic row = await supabase.rpc('record_payment', params: <String, dynamic>{
        'p_invoice_id': invoiceId,
        'p_amount': amount,
        'p_payment_mode': paymentMode,
        'p_payment_date': DateTime.now().toIso8601String(),
        'p_customer_id': customerId,
        'p_sale_id': saleId,
        'p_reference_number': referenceNumber,
        'p_is_down_payment': isDownPayment,
        'p_notes': notes,
      });
      if (row is! Map) {
        throw AppException('record_payment returned no payment row.');
      }
      return PaymentModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Refunds (voids) a payment (transactional RPC).
  Future<void> refund(String paymentId, String reason,
      {String? referenceNumber}) async {
    try {
      await supabase.rpc('refund_payment', params: <String, dynamic>{
        'p_payment_id': paymentId,
        'p_reason': reason,
        'p_reference_number': referenceNumber,
      });
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Outstanding balance on an invoice.
  Future<num> outstandingForInvoice(String invoiceId) async {
    try {
      final dynamic row = await supabase
          .table('invoices')
          .select('outstanding_amount')
          .eq('id', invoiceId)
          .maybeSingle();
      if (row is! Map) return 0;
      return SafeJson.asMoney(row['outstanding_amount']);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Resolves the (first) invoice of a sale — used when "Receive Payment"
  /// is opened from the sale details screen.
  Future<String?> invoiceIdForSale(String saleId) async {
    try {
      final dynamic row = await supabase
          .table('sales')
          .select('invoices(*)')
          .eq('id', saleId)
          .maybeSingle();
      if (row is! Map) return null;
      final List<dynamic> invoices = SafeJson.asList(row['invoices']);
      if (invoices.isEmpty) return null;
      final dynamic first = invoices.first;
      if (first is! Map) return null;
      return SafeJson.asId(first['id']);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Basic customer lookup for the payment form (id → name/phone).
  Future<Map<String, dynamic>?> customerSummary(String customerId) async {
    try {
      final dynamic row = await supabase
          .table('customers')
          .select()
          .eq('id', customerId)
          .maybeSingle();
      if (row is! Map) return null;
      return SafeJson.asMap(row);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}
