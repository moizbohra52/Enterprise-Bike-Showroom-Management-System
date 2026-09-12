import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A role (e.g. `SHOWROOM MANAGER`). System roles cannot be deleted.
class RoleModel extends BaseModel {
  RoleModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    required this.name,
    this.description = '',
    this.isSystemRole = false,
    this.permissionCount = 0,
  });

  /// Role name (unique, e.g. `SALES STAFF`).
  final String name;
  final String description;
  final bool isSystemRole;

  /// Number of permissions attached (populated by list queries).
  final int permissionCount;

  factory RoleModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return RoleModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      name: SafeJson.asText(json['name']),
      description: SafeJson.asText(json['description']),
      isSystemRole: SafeJson.asBoolOr(json['is_system_role'], false),
      permissionCount: SafeJson.asIntOr(json['permission_count'], 0),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'name': name,
        'description': description,
        'is_system_role': isSystemRole,
      };

  RoleModel copyWith({
    String? id,
    String? name,
    String? description,
    bool? isSystemRole,
    int? permissionCount,
  }) {
    return RoleModel(
      id: id ?? this.id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      name: name ?? this.name,
      description: description ?? this.description,
      isSystemRole: isSystemRole ?? this.isSystemRole,
      permissionCount: permissionCount ?? this.permissionCount,
    );
  }

  /// Human friendly title.
  String get label =>
      name.replaceAll('_', ' ').split(' ').map((String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
}
