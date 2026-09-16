import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// Centralized access to the Supabase client (PostgREST, Auth, Storage,
/// Realtime, RPC).
///
/// Repositories use this service instead of touching
/// `Supabase.instance.client` directly, which keeps one place for:
/// - RPC result shaping
/// - error mapping to [AppException]
/// - logging
class SupabaseService {
  SupabaseService();

  /// The underlying Supabase client (initialized in `main.dart`).
  SupabaseClient get client => Supabase.instance.client;

  /// Table query builder shortcut: `from('customers')`.
  SupabaseQueryBuilder table(String table) => client.from(table);

  /// Realtime channel helper.
  RealtimeChannel channel(String name) => client.realtime.channel(name);

  /// Calls a Postgres function and returns its single jsonb row.
  Future<Map<String, dynamic>> rpc(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    AppLogger.debug('RPC', '→ $function', error: _logSafe(params));
    try {
      final dynamic result = await client.rpc(function, params: params);
      if (result is Map<String, dynamic>) return result;
      if (result is Map) {
        return <String, dynamic>{
          for (final MapEntry<dynamic, dynamic> e in result.entries)
            e.key.toString(): e.value,
        };
      }
      return <String, dynamic>{'data': result};
    } on PostgrestException catch (e) {
      AppLogger.error('RPC', '← $function failed', error: e.message);
      throw ErrorMapper.map(e);
    } catch (e) {
      AppLogger.error('RPC', '← $function failed', error: e);
      throw ErrorMapper.map(e);
    }
  }

  /// Calls a function that returns a jsonb array.
  Future<List<Map<String, dynamic>>> rpcList(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    final dynamic result = await _rawRpc(function, params);
    final List<dynamic> rows = SafeJson.asList(result);
    return <Map<String, dynamic>>[
      for (final dynamic row in rows)
        if (row is Map) SafeJson.asMap(row),
    ];
  }

  /// Calls a function that returns a single scalar (uuid / numeric / bool).
  Future<dynamic> rpcScalar(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    return _rawRpc(function, params);
  }

  Future<dynamic> _rawRpc(String function, Map<String, dynamic>? params) async {
    try {
      return await client.rpc(function, params: params);
    } on PostgrestException catch (e) {
      throw ErrorMapper.map(e);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// True when the configured backend is still the dev placeholder.
  bool get isConfigured => !SupabaseConfig.url.contains('placeholder');

  dynamic _logSafe(Map<String, dynamic>? params) {
    if (params == null) return null;
    return <String, dynamic>{
      for (final MapEntry<String, dynamic> e in params.entries)
        e.key: e.value is Map ? '<json>' : e.value,
    };
  }
}

/// Extension making `select` count usage explicit and consistent.
///
/// PostgREST v2+ uses chained `.count(CountOption.exact)` instead of the
/// deprecated `select(columns, count: …)` named argument.
extension SupabaseQueryX on SupabaseQueryBuilder {
  /// Builds `select(columns)` for paginated reads.
  /// Callers should chain filters, then finish with `.count(CountOption.exact)`.
  PostgrestFilterBuilder withExactCount([String columns = '*']) {
    return select(columns);
  }
}

/// Helpers for reading the count off a PostgREST response.
extension PostgrestResponseCountX on dynamic {
  /// Best-effort count extraction from a PostgrestResponse / list response.
  int get exactCount {
    try {
      // ignore: avoid_dynamic_calls
      final dynamic c = this.count;
      if (c is int) return c;
      if (c is num) return c.toInt();
    } catch (_) {}
    return 0;
  }
}
