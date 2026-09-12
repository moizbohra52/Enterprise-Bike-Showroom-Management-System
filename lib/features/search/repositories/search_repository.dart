import 'package:enterprise_bike_showroom/features/search/models/search_result_model.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Global search backed by the `global_search` Postgres function.
class SearchRepository {
  SearchRepository(this.supabase);

  final SupabaseService supabase;

  /// Searches customers, vehicles (registration/chassis/engine), invoices,
  /// sales, payments, loans, EMIs and services for [term].
  Future<List<SearchResultModel>> search(String term, {int limit = 20}) async {
    if (term.trim().isEmpty) return <SearchResultModel>[];
    final List<Map<String, dynamic>> rows = await supabase.rpcList(
      'global_search',
      params: <String, dynamic>{
        'p_query': term.trim(),
        'p_limit': limit,
      },
    );
    return <SearchResultModel>[
      for (final Map<String, dynamic> row in rows)
        SearchResultModel.fromJson(row),
    ];
  }
}
