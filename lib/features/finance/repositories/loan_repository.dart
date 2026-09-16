import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/finance/models/loan_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for loans and EMI schedules.
class LoanRepository {
  LoanRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<LoanModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('loans')
          .select('*, customer:customers(name, phone)');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'loan_number.ilike.%$term%,customer:customers(name).ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<LoanModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => LoanModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<LoanModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('loans')
          .select('*, customer:customers(name, phone)')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return LoanModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// The full EMI schedule for a loan.
  Future<List<EmiScheduleModel>> schedule(String loanId) async {
    try {
      final dynamic rows = await supabase
          .table('emi_schedules')
          .select()
          .eq('loan_id', loanId)
          .order('installment_no');
      return <EmiScheduleModel>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) EmiScheduleModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Pays one (or more) installment(s) through the transactional RPC.
  /// Returns the updated schedule rows.
  Future<List<EmiScheduleModel>> payEmi({
    required String loanId,
    required int installmentNo,
    required String paymentMode,
    String? referenceNumber,
    String? notes,
  }) async {
    try {
      final dynamic row = await supabase.rpc('pay_emi', params: <String, dynamic>{
        'p_loan_id': loanId,
        'p_installment_no': installmentNo,
        'p_payment_mode': paymentMode,
        'p_payment_date': DateTime.now().toIso8601String(),
        'p_reference_number': referenceNumber,
        'p_notes': notes,
      });
      if (row is Map) {
        final List<dynamic> list = SafeJson.asList(row['schedule']);
        return <EmiScheduleModel>[
          for (final dynamic item in list)
            if (item is Map) EmiScheduleModel.fromJson(SafeJson.asMap(item)),
        ];
      }
      return schedule(loanId);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Next due installment for a loan (for quick action + reminders).
  Future<EmiScheduleModel?> nextDue(String loanId) async {
    final List<EmiScheduleModel> rows = await schedule(loanId);
    final DateTime now = DateTime.now();
    EmiScheduleModel? next;
    for (final EmiScheduleModel row in rows) {
      if (row.status == 'paid' || row.status == 'cancelled') continue;
      if (row.dueDate.isAfter(now) && next == null) return row;
      if (next == null && row.dueDate.isBefore(now)) next = row;
    }
    return next;
  }
}

/// Marker used by callers to surface RPC-level failures.
typedef LoanFlowException = AppException;
