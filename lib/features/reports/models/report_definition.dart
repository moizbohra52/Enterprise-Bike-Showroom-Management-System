import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A report definition (metadata + how to fetch rows).
class ReportDefinition {
  const ReportDefinition({
    required this.key,
    required this.title,
    required this.description,
    required this.source,
    required this.columns,
    this.defaultParams = const <String, dynamic>{},
  });

  final String key;
  final String title;
  final String description;

  /// SQL view / RPC name backing the report.
  final String source;
  final List<String> columns;
  final Map<String, dynamic> defaultParams;

  /// Maps a raw row to display strings, using the definition's columns.
  List<String> rowToDisplay(Map<String, dynamic> row) {
    return <String>[
      for (final String column in columns)
        _display(row[column]),
    ];
  }

  String _display(dynamic value) {
    if (value == null) return '-';
    if (value is num) {
      return SafeJson.asMoney(value).toString();
    }
    final String s = value.toString();
    return s;
  }
}
