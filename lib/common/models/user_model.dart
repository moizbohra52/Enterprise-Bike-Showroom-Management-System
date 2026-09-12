import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/common/models/role_model.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// Application user profile (the `users` table + joined roles/permissions/
/// showrooms).
class UserModel extends BaseModel {
  UserModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.authUserId,
    this.showroomId,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.status = 'active',
    this.avatarUrl,
    this.lastLoginAt,
    this.isSuperAdmin = false,
    this.roles = const <RoleModel>[],
    this.permissions = const <String>[],
    this.showrooms = const <ShowroomModel>[],
  });

  /// Supabase `auth.users.id` (unique).
  final String? authUserId;

  /// Home showroom (first assignment).
  final String? showroomId;
  final String name;
  final String email;
  final String phone;
  final String status;
  final String? avatarUrl;
  final DateTime? lastLoginAt;

  /// True when the user holds the SUPER ADMIN role.
  final bool isSuperAdmin;

  /// Roles of this user.
  final List<RoleModel> roles;

  /// Effective permission strings (`module.action`).
  final List<String> permissions;

  /// Showrooms this user may access.
  final List<ShowroomModel> showrooms;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return UserModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      authUserId: SafeJson.asId(json['auth_user_id']),
      showroomId: SafeJson.asId(json['showroom_id']),
      name: SafeJson.asText(json['name']),
      email: SafeJson.asText(json['email']),
      phone: SafeJson.asText(json['phone']),
      status: SafeJson.asText(json['status'], fallback: 'active'),
      avatarUrl: SafeJson.asString(json['avatar_url']),
      lastLoginAt: SafeJson.asDate(json['last_login_at']),
      isSuperAdmin: SafeJson.asBoolOr(json['is_super_admin'], false),
      roles: <RoleModel>[
        for (final dynamic r in SafeJson.asList(json['roles']))
          if (r is Map)
            RoleModel.fromJson(SafeJson.asMap(r)),
      ],
      permissions: <String>[
        for (final dynamic p in SafeJson.asList(json['permissions']))
          p.toString(),
      ],
      showrooms: <ShowroomModel>[
        for (final dynamic s in SafeJson.asList(json['showrooms']))
          if (s is Map)
            ShowroomModel.fromJson(SafeJson.asMap(s)),
      ],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'auth_user_id': authUserId,
        'showroom_id': showroomId,
        'name': name,
        'email': email,
        'phone': phone,
        'status': status,
        'avatar_url': avatarUrl,
        if (lastLoginAt != null)
          'last_login_at': lastLoginAt!.toIso8601String(),
        'is_super_admin': isSuperAdmin,
        'roles': <dynamic>[
          for (final RoleModel r in roles) r.toJson(),
        ],
        'permissions': permissions,
        'showrooms': <dynamic>[
          for (final ShowroomModel s in showrooms) s.toJson(),
        ],
      };

  UserModel copyWith({
    String? id,
    String? authUserId,
    String? showroomId,
    String? name,
    String? email,
    String? phone,
    String? status,
    String? avatarUrl,
    DateTime? lastLoginAt,
    bool? isSuperAdmin,
    List<RoleModel>? roles,
    List<String>? permissions,
    List<ShowroomModel>? showrooms,
  }) {
    return UserModel(
      id: id ?? this.id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      authUserId: authUserId ?? this.authUserId,
      showroomId: showroomId ?? this.showroomId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      roles: roles ?? this.roles,
      permissions: permissions ?? this.permissions,
      showrooms: showrooms ?? this.showrooms,
    );
  }

  /// Human readable role labels.
  List<String> get roleLabels =>
      roles.map((RoleModel r) => r.label).toList(growable: false);
}
