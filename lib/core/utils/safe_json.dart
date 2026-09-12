import 'dart:convert';

/// Defensive JSON parsing helpers.
///
/// Supabase/Postgres can return values in several shapes (null, String,
/// num, DateTime, Map, List). Models should never crash on an unexpected
/// shape - use these helpers instead of raw casts.
class SafeJson {
  SafeJson._();

  /// UUID / identifier field.
  static String? asId(dynamic value) {
    if (value == null) return null;
    final String s = value.toString();
    return s.isEmpty ? null : s;
  }

  /// String field.
  static String? asString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  /// String field with a fallback.
  static String asText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final String s = value.toString();
    return s.isEmpty ? fallback : s;
  }

  /// Numeric field (accepts int, double, numeric string).
  static num? asNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return double.tryParse(value.toString());
  }

  /// Numeric field with zero fallback (money fields).
  static num asMoney(dynamic value) => asNum(value) ?? 0;

  /// Integer field.
  static int? asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  /// Integer field with fallback.
  static int asIntOr(dynamic value, int fallback) => asInt(value) ?? fallback;

  /// Boolean field.
  static bool? asBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final String s = value.toString().toLowerCase();
    if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
    return null;
  }

  /// Boolean field with fallback.
  static bool asBoolOr(dynamic value, bool fallback) =>
      asBool(value) ?? fallback;

  /// Date/time field (ISO strings from Postgres `timestamptz`/`date`).
  static DateTime? asDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// Date field (ignores time part).
  static DateTime? asDay(dynamic value) {
    final DateTime? d = asDate(value);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  /// List field.
  static List<dynamic> asList(dynamic value) {
    if (value is List) return value;
    if (value is String && value.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } catch (_) {
        // fall through
      }
    }
    return <dynamic>[];
  }

  /// Map / JSONB field.
  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return <String, dynamic>{
        for (final MapEntry<dynamic, dynamic> e in value.entries)
          e.key.toString(): e.value,
      };
    }
    if (value is String && value.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // fall through
      }
    }
    return <String, dynamic>{};
  }

  /// JSON-encodes any value, passing through already-JSON strings.
  static String? asJsonString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return jsonEncode(value);
  }
}
