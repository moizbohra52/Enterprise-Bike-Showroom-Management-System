import 'package:enterprise_bike_showroom/core/utils/date_utils.dart';
import 'package:enterprise_bike_showroom/core/utils/id_generator.dart';

/// Client-side document number preview.
///
/// The authoritative document number is generated server-side inside the
/// RPC transactions (`create_sale_transaction`, `record_payment`, ...).
/// This generator is used to show a *preview* number on forms and to tag
/// offline-draft payloads so the UI can reference them.
class DocNumberGenerator {
  DocNumberGenerator._();

  /// Builds a number like `SAL-2026-09-12-A1B2` for `prefix = 'SAL'`.
  static String preview({
    required String prefix,
    DateTime? date,
  }) {
    final DateTime d = date ?? DateTime.now();
    final String datePart =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final String tail = IdGenerator.uuid().substring(0, 4).toUpperCase();
    return '$prefix-$datePart-$tail';
  }

  /// Builds an offline-prefixed number, e.g. `OFF-CUS-8F3K`.
  static String offlinePreview({required String prefix}) {
    final String tail = IdGenerator.uuid().substring(0, 4).toUpperCase();
    return 'OFF-$prefix-$tail';
  }

  /// Formats a server-issued number for display (adds missing separators).
  static String display(String? number) {
    if (number == null || number.isEmpty) return '-';
    return number.toUpperCase();
  }

  /// Today's label used in reports, e.g. `12 Sep 2026`.
  static String todayLabel() => DateUtils.format(DateTime.now());
}
