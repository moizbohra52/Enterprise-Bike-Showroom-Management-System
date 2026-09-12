import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/accounting/models/accounting_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for the double-entry ledger.
class AccountingRepository {
  AccountingRepository(this.supabase);

  final SupabaseService supabase;

  // ------------------------------------------------------------ accounts

  Future<PaginatedResponse<AccountModel>> listAccounts(PageQuery query) async {
    try {
      var builder = supabase
          .table('accounts')
          .select('*', count: CountOption.exact)
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or('code.ilike.%$term%,name.ilike.%$term%');
      }
      final String? type = SafeJson.asString(query.filters['type']);
      if (type != null && type.isNotEmpty) builder = builder.eq('type', type);
      builder = builder.order('code', ascending: true);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<AccountModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => AccountModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// All active accounts (for pickers in manual-entry forms).
  Future<List<AccountModel>> allAccounts() async {
    try {
      final dynamic rows = await supabase
          .table('accounts')
          .select()
          .eq('status', 'active')
          .order('code');
      return <AccountModel>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) AccountModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Creates an account (manual extension of the default chart).
  Future<AccountModel> createAccount(Map<String, dynamic> payload) async {
    try {
      final dynamic row = await supabase
          .table('accounts')
          .insert(payload)
          .select()
          .single();
      return AccountModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ------------------------------------------------------------- journals

  Future<PaginatedResponse<JournalEntryModel>> listJournals(PageQuery query) async {
    try {
      var builder = supabase
          .table('journal_entries')
          .select('*', count: CountOption.exact)
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'entry_number.ilike.%$term%,narration.ilike.%$term%',
        );
      }
      final String? source =
          SafeJson.asString(query.filters['source_module']);
      if (source != null && source.isNotEmpty) {
        builder = builder.eq('source_module', source);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<JournalEntryModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) =>
            JournalEntryModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<JournalEntryModel?> journalById(String id) async {
    try {
      final dynamic row = await supabase
          .table('journal_entries')
          .select('*, journal_lines(*, accounts(code, name))')
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return JournalEntryModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Manual journal entry via the transactional RPC (validates DR = CR).
  Future<JournalEntryModel> createManualEntry({
    required String showroomId,
    required DateTime entryDate,
    required String narration,
    required List<JournalLineModel> lines,
  }) async {
    final num totalDebit = lines
        .where((JournalLineModel l) => l.side == 'debit')
        .fold<num>(0, (num sum, JournalLineModel l) => sum + l.amount);
    final num totalCredit = lines
        .where((JournalLineModel l) => l.side == 'credit')
        .fold<num>(0, (num sum, JournalLineModel l) => sum + l.amount);
    if (totalDebit != totalCredit || totalDebit == 0) {
      throw AppException(
          'Entry is unbalanced: debit ${totalDebit} vs credit ${totalCredit}.');
    }
    try {
      final dynamic row = await supabase.rpc(
          'create_accounting_transaction',
          <String, dynamic>{
            'showroom_id': showroomId,
            'entry_date': entryDate.toIso8601String(),
            'narration': narration,
            'source_module': 'manual',
            'lines': <Map<String, dynamic>>[
              for (final JournalLineModel line in lines)
                line.toJson(),
            ],
          });
      if (row is! Map) {
        throw AppException('create_accounting_transaction returned no row.');
      }
      return JournalEntryModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Account ledger (all lines touching the account, with running balance).
  Future<List<Map<String, dynamic>>> accountLedger(
      String accountId, {int limit = 500}) async {
    try {
      final dynamic rows = await supabase.rpc('account_ledger', <String, dynamic>{
        'p_account_id': accountId,
        'p_limit': limit,
      });
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}
