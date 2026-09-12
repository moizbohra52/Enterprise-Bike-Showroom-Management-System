import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// An in-app notification row (also mirrored as FCM push).
class NotificationModel extends BaseModel {
  NotificationModel({
    super.id,
    super.createdAt,
    this.showroomId,
    this.customerId,
    this.title = '',
    this.message = '',
    this.type = NotificationType.system,
    this.referenceId,
    this.referenceType,
    this.isRead = false,
    this.sentAt,
  });

  final String? showroomId;
  final String? customerId;
  final String title;
  final String message;
  final NotificationType type;
  final String? referenceId;
  final String? referenceType;
  final bool isRead;
  final DateTime? sentAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return NotificationModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      customerId: SafeJson.asId(json['customer_id']),
      title: SafeJson.asText(json['title']),
      message: SafeJson.asText(json['message']),
      type: NotificationType.fromWire(SafeJson.asString(json['notification_type'])),
      referenceId: SafeJson.asId(json['reference_id']),
      referenceType: SafeJson.asString(json['reference_type']),
      isRead: SafeJson.asBoolOr(json['is_read'], false),
      sentAt: SafeJson.asDate(json['sent_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'customer_id': customerId,
        'title': title,
        'message': message,
        'notification_type': type.value,
        'reference_id': referenceId,
        'reference_type': referenceType,
        'is_read': isRead,
        if (sentAt != null) 'sent_at': sentAt!.toIso8601String(),
      };

  NotificationModel copyWith({
    String? id,
    bool? isRead,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      showroomId: showroomId,
      customerId: customerId,
      title: title,
      message: message,
      type: type,
      referenceId: referenceId,
      referenceType: referenceType,
      isRead: isRead ?? this.isRead,
      sentAt: sentAt,
    );
  }
}

/// FCM device token row.
class DeviceTokenModel extends BaseModel {
  DeviceTokenModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    required this.userId,
    required this.deviceToken,
    this.platform = 'android',
    this.deviceName = '',
    this.isActive = true,
    this.lastSeenAt,
  });

  final String userId;
  final String deviceToken;
  final String platform;
  final String deviceName;
  final bool isActive;
  final DateTime? lastSeenAt;

  factory DeviceTokenModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return DeviceTokenModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      userId: SafeJson.asText(json['user_id']),
      deviceToken: SafeJson.asText(json['device_token']),
      platform: SafeJson.asText(json['platform'], fallback: 'android'),
      deviceName: SafeJson.asText(json['device_name']),
      isActive: SafeJson.asBoolOr(json['is_active'], true),
      lastSeenAt: SafeJson.asDate(json['last_seen_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'user_id': userId,
        'device_token': deviceToken,
        'platform': platform,
        'device_name': deviceName,
        'is_active': isActive,
        if (lastSeenAt != null) 'last_seen_at': lastSeenAt!.toIso8601String(),
      };
}
