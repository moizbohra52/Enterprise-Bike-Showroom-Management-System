import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// One row in a global search result set.
class SearchResultModel extends BaseModel {
  SearchResultModel({
    required this.entityType,
    required this.id,
    required this.title,
    this.subtitle,
    this.route,
  });

  /// Entity type, e.g. `customer`, `inventory`, `invoice`.
  final String entityType;
  final String id;
  final String title;
  final String? subtitle;

  /// Optional direct route (used for navigation).
  final String? route;

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      entityType: SafeJson.asText(json['entity_type'], fallback: 'unknown'),
      id: SafeJson.asText(json['id']),
      title: SafeJson.asText(json['title']),
      subtitle: SafeJson.asString(json['subtitle']),
      route: SafeJson.asString(json['route']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entity_type': entityType,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'route': route,
      };
}
