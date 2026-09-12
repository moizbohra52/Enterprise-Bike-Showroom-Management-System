import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A single `module.action` permission.
class PermissionModel extends BaseModel {
  PermissionModel({
    super.id,
    super.createdAt,
    required this.module,
    required this.action,
    this.description = '',
  });

  final String module;
  final String action;
  final String description;

  /// Canonical string: `module.action`.
  String get value => '$module.$action';

  factory PermissionModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return PermissionModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      module: SafeJson.asText(json['module']),
      action: SafeJson.asText(json['action']),
      description: SafeJson.asText(json['description']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'module': module,
        'action': action,
        'description': description,
      };

  PermissionModel copyWith({
    String? id,
    String? module,
    String? action,
    String? description,
  }) {
    return PermissionModel(
      id: id ?? this.id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      module: module ?? this.module,
      action: action ?? this.action,
      description: description ?? this.description,
    );
  }
}
