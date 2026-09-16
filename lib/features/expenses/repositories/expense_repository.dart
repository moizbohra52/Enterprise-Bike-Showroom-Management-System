import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/expenses/models/expense_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for expenses and expense categories.
///
/// Expense creation is the transactional RPC `create_expense_transaction`;
/// approval / rejection are `approve_expense` / `reject_expense`.
class ExpenseRepository {
  ExpenseRepository(this.supabase);

  final SupabaseService supabase;

  // ----------------------------------------------------------- categories

  Future<List<ExpenseCategoryModel>> categories({String? showroomId}) async {
    try {
      dynamic builder = supabase
          .table('expense_categories')
          .select()
          .eq('status', 'active');
      if (showroomId != null && showroomId.isNotEmpty) {
        builder = builder.or('showroom_id.is.null,showroom_id.eq.$showroomId');
      }
      builder = builder.order('name');
      final dynamic rows = await builder;
      return <ExpenseCategoryModel>[
        for (final dynamic row in SafeJson.asList(rows));
          if (row is Map)
            ExpenseCategoryModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ExpenseCategoryModel> createCategory(
      Map<String, dynamic> payload) async {
    try {
      final dynamic row = await supabase
          .table('expense_categories')
          .insert(payload)
          .select()
          .single();
      return ExpenseCategoryModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // -------------------------------------------------------------- expenses

  Future<PaginatedResponse<ExpenseModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('expenses')
          .select('*, category:expense_categories(name, icon)');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'expense_number.ilike.%$term%,description.ilike.%$term%,voucher_number.ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      final String? categoryId =
          SafeJson.asString(query.filters['category_id']);
      if (categoryId != null && categoryId.isNotEmpty) {
        builder = builder.eq('category_id', categoryId);
      }
      final String? from = SafeJson.asString(query.filters['date_from']);
      final String? to = SafeJson.asString(query.filters['date_to']);
      if (from != null && from.isNotEmpty) builder = builder.gte('date', from);
      if (to != null && to.isNotEmpty) builder = builder.lte('date', to);
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<ExpenseModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => ExpenseModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ExpenseModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('expenses')
          .select('*, category:expense_categories(name, icon)')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return ExpenseModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Creates an expense (transactional RPC: expense + ledger).
  Future<ExpenseModel> create({
    required String categoryId,
    required String showroomId,
    required String description,
    required num amount,
    required DateTime date,
    String paymentMode = 'cash',
    String? referenceNumber,
    String? voucherNumber,
    String? attachmentPath,
    String? notes,
  }) async {
    try {
      final dynamic row = await supabase.rpc(
          'create_expense_transaction',
          params: <String, dynamic>{
            'category_id': categoryId,
            'showroom_id': showroomId,
            'description': description,
            'amount': amount,
            'date': date.toIso8601String(),
            'payment_mode': paymentMode,
            'reference_number': referenceNumber,
            'voucher_number': voucherNumber,
            'attachment_path': attachmentPath,
            'notes': notes,
          });
      if (row is! Map) {
        throw AppException('create_expense_transaction returned no row.');
      }
      return ExpenseModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ExpenseModel> approve(String id, String approvedBy) async {
    try {
      final dynamic row = await supabase.rpc('approve_expense', params: <String, dynamic>{
        'p_expense_id': id,
        'p_approved_by': approvedBy,
      });
      if (row is! Map) {
        throw AppException('approve_expense returned no row.');
      }
      return ExpenseModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ExpenseModel> reject(
      String id, String rejectedBy, String reason) async {
    try {
      final dynamic row = await supabase.rpc('reject_expense', params: <String, dynamic>{
        'p_expense_id': id,
        'p_rejected_by': rejectedBy,
        'p_reason': reason,
      });
      if (row is! Map) {
        throw AppException('reject_expense returned no row.');
      }
      return ExpenseModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}
