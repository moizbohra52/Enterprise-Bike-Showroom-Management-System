import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// Base class for all domain models.
///
/// Provides shared timestamp parsing and a base JSON envelope. Subclasses
/// implement `fromJson` / `toJson` / `copyWith` (all public per project
/// coding standards).
class BaseModel {
  BaseModel({this.id, this.createdAt, this.updatedAt});

  /// Primary key (uuid).
  final String? id;

  /// Row creation time.
  final DateTime? createdAt;

  /// Last modification time.
  final DateTime? updatedAt;

  /// Parses an id field tolerantly.
  static String? parseId(dynamic value) => SafeJson.asId(value);

  /// Parses a timestamp field tolerantly.
  static DateTime? parseDate(dynamic value) => SafeJson.asDate(value);

  /// Base JSON envelope (id/timestamps).
  Map<String, dynamic> toBaseJson() => <String, dynamic>{
        if (id != null) 'id': id,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  /// Parses id/timestamps from a JSON row into local vars.
  Map<String, dynamic> baseFromJson(Map<String, dynamic> json) =>
      <String, dynamic>{
        'id': SafeJson.asId(json['id']),
        'createdAt': SafeJson.asDate(json['created_at']),
        'updatedAt': SafeJson.asDate(json['updated_at']),
      };

  @override
  String toString() => runtimeType.toString();
}
