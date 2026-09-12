import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A document / attachment linked to any business entity.
class AttachmentModel extends BaseModel {
  AttachmentModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    this.userId,
    this.entityType = '',
    this.entityId = '',
    this.fileName = '',
    this.mimeType = '',
    this.fileSize = 0,
    this.storagePath = '',
    this.notes = '',
  });

  final String? showroomId;
  final String? userId;
  final String entityType; // customer | vehicle | invoice | service | ...
  final String entityId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String storagePath;
  final String notes;

  factory AttachmentModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return AttachmentModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      userId: SafeJson.asId(json['user_id']),
      entityType: SafeJson.asText(json['entity_type']),
      entityId: SafeJson.asText(json['entity_id']),
      fileName: SafeJson.asText(json['file_name']),
      mimeType: SafeJson.asText(json['mime_type']),
      fileSize: SafeJson.asIntOr(json['file_size'], 0),
      storagePath: SafeJson.asText(json['storage_path']),
      notes: SafeJson.asText(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'user_id': userId,
        'entity_type': entityType,
        'entity_id': entityId,
        'file_name': fileName,
        'mime_type': mimeType,
        'file_size': fileSize,
        'storage_path': storagePath,
        'notes': notes,
      };

  String get sizeLabel {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// An audit-log row (immutable).
class AuditLogModel extends BaseModel {
  AuditLogModel({
    super.id,
    super.createdAt,
    this.showroomId,
    this.userId,
    this.userName = '',
    this.action = '',
    this.entityType = '',
    this.entityId = '',
    this.oldValues = const <String, dynamic>{},
    this.newValues = const <String, dynamic>{},
    this.ipAddress = '',
    this.userAgent = '',
    this.notes = '',
  });

  final String? showroomId;
  final String? userId;
  final String userName;
  final String action; // create | update | delete | login | ...
  final String entityType;
  final String entityId;
  final Map<String, dynamic> oldValues;
  final Map<String, dynamic> newValues;
  final String ipAddress;
  final String userAgent;
  final String notes;

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return AuditLogModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      userId: SafeJson.asId(json['user_id']),
      userName: SafeJson.asText(json['user_name']),
      action: SafeJson.asText(json['action']),
      entityType: SafeJson.asText(json['entity_type']),
      entityId: SafeJson.asText(json['entity_id']),
      oldValues: SafeJson.asMap(json['old_values']),
      newValues: SafeJson.asMap(json['new_values']),
      ipAddress: SafeJson.asText(json['ip_address']),
      userAgent: SafeJson.asText(json['user_agent']),
      notes: SafeJson.asText(json['notes']),
    );
  }

  Map<String, dynamic> get changes {
    final Map<String, dynamic> changed = <String, dynamic>{};
    final Set<String> keys = <String>{
      ...oldValues.keys,
      ...newValues.keys,
    };
    for (final String key in keys) {
      final dynamic a = oldValues[key];
      final dynamic b = newValues[key];
      if (a?.toString() != b?.toString()) {
        changed[key] = <String, dynamic>{
          'from': a?.toString() ?? '-',
          'to': b?.toString() ?? '-',
        };
      }
    }
    return changed;
  }
}
