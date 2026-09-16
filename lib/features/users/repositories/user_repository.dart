import 'package:enterprise_bike_showroom/common/models/permission_model.dart';
import 'package:enterprise_bike_showroom/common/models/role_model.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/common/models/user_model.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for users, roles and permissions.
///
/// Remote-first; reads go through Supabase PostgREST with RLS enforcing
/// access. User mutations while offline are queued for sync.
class UserRepository {
  UserRepository(this.supabase);

  final SupabaseService supabase;

  static const String _table = 'users';

  /// The profile of the signed-in auth user with roles, permissions and
  /// accessible showrooms.
  Future<UserModel?> currentProfile() async {
    try {
      final String? authUserId = supabase.client.auth.currentUser?.id;
      if (authUserId == null) return null;

      final dynamic row = await supabase
          .table(_table)
          .select()
          .eq('auth_user_id', authUserId)
          .maybeSingle();
      if (row is! Map) return null;
      final Map<String, dynamic> json = SafeJson.asMap(row);
      final String? userId = SafeJson.asId(json['id']);

      final List<RoleModel> roles = await _rolesFor(userId);
      final bool isSuperAdmin = roles.any((RoleModel r) => r.name == 'SUPER ADMIN');

      final List<String> permissions =
          isSuperAdmin ? <String>[Permissions_all] : await _permissionsFor(roles);
      final List<ShowroomModel> showrooms = await _showrooms(json, isSuperAdmin);

      return UserModel.fromJson(json).copyWith(
        isSuperAdmin: isSuperAdmin,
        roles: roles,
        permissions: permissions,
        showrooms: showrooms,
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Wildcard permission granted to SUPER ADMIN.
  static const String Permissions_all = '*.*';

  Future<List<RoleModel>> _rolesFor(String? userId) async {
    if (userId == null) return <RoleModel>[];
    final List<String> roleIds = await _roleIdsFor(userId);
    if (roleIds.isEmpty) return <RoleModel>[];
    final dynamic rows =
        await supabase.table('roles').select().inFilter('id', roleIds);
    return <RoleModel>[
      for (final dynamic r in SafeJson.asList(rows))
        if (r is Map) RoleModel.fromJson(SafeJson.asMap(r)),
    ];
  }

  /// Role ids currently assigned to [userId].
  Future<List<String>> roleIdsFor(String userId) => _roleIdsFor(userId);

  Future<List<String>> _roleIdsFor(String userId) async {
    final dynamic rows = await supabase
        .table('user_roles')
        .select('role_id')
        .eq('user_id', userId);
    return <String>[
      for (final dynamic r in SafeJson.asList(rows))
        if (r is Map) SafeJson.asText(r['role_id']),
    ].where((String id) => id.isNotEmpty).toList();
  }

  Future<List<String>> _permissionsFor(List<RoleModel> roles) async {
    if (roles.isEmpty) return <String>[];
    final List<String> roleIds = <String>[
      for (final RoleModel r in roles)
        if (r.id != null) r.id!,
    ];
    if (roleIds.isEmpty) return <String>[];
    final dynamic rows = await supabase
        .table('role_permissions')
        .select('permission_id')
        .inFilter('role_id', roleIds);
    final List<String> permissionIds = <String>[
      for (final dynamic r in SafeJson.asList(rows))
        if (r is Map) SafeJson.asText(r['permission_id']),
    ].where((String id) => id.isNotEmpty).toList();
    if (permissionIds.isEmpty) return <String>[];
    final dynamic perms = await supabase
        .table('permissions')
        .select('module, action')
        .inFilter('id', permissionIds);
    return <String>[
      for (final dynamic p in SafeJson.asList(perms))
        if (p is Map)
          '${SafeJson.asText(p['module'])}.${SafeJson.asText(p['action'])}',
    ].where((String s) => s != '.').toList()..sort();
  }

  Future<List<ShowroomModel>> _showrooms(
      Map<String, dynamic> userJson, bool isSuperAdmin) async {
    if (isSuperAdmin) {
      final dynamic rows = await supabase
          .table('showrooms')
          .select()
          .eq('status', 'active')
          .order('code');
      return <ShowroomModel>[
        for (final dynamic r in SafeJson.asList(rows))
          if (r is Map) ShowroomModel.fromJson(SafeJson.asMap(r)),
      ];
    }
    final String? showroomId = SafeJson.asId(userJson['showroom_id']);
    if (showroomId == null) return <ShowroomModel>[];
    final dynamic row = await supabase
        .table('showrooms')
        .select()
        .eq('id', showroomId)
        .maybeSingle();
    if (row is Map) {
      return <ShowroomModel>[ShowroomModel.fromJson(SafeJson.asMap(row))];
    }
    return <ShowroomModel>[];
  }

  /// Paginated user list with optional search/status/showroom filters.
  Future<PaginatedResponse<UserModel>> list(PageQuery query) async {
    try {
      final String? searchTerm = query.search;
      final String? status = SafeJson.asString(query.filters['status']);
      final String? showroomId =
          SafeJson.asString(query.filters['showroom_id']);

      dynamic builder = supabase
          .table(_table)
          .select('*');
      if (searchTerm != null && searchTerm.isNotEmpty) {
        builder = builder.or(
          'name.ilike.%$searchTerm%,email.ilike.%$searchTerm%,phone.ilike.%$searchTerm%',
        );
      }
      if (status != null && status.isNotEmpty) builder = builder.eq('status', status);
      if (showroomId != null && showroomId.isNotEmpty) {
        builder = builder.eq('showroom_id', showroomId);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);

      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      final int total = _countOf(result);
      final List<dynamic> rows = SafeJson.asList(result);
      return PaginatedResponse<UserModel>.fromSupabase(
        rows,
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => UserModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  int _countOf(dynamic result) {
    try {
      // PostgrestList carries `.count` when CountOption.exact is used.
      // ignore: avoid_dynamic_calls
      final dynamic count = result.count;
      return SafeJson.asIntOr(count, 0);
    } catch (_) {
      return SafeJson.asList(result).length;
    }
  }

  Future<UserModel?> getById(String id) async {
    try {
      final dynamic row =
          await supabase.table(_table).select().eq('id', id).maybeSingle();
      if (row is! Map) return null;
      return UserModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Creates a user profile after the Supabase auth account exists.
  Future<UserModel> createProfile({
    required String authUserId,
    required String name,
    required String email,
    String? phone,
    String? showroomId,
    List<String> roleIds = const <String>[],
  }) async {
    try {
      final dynamic row = await supabase.table(_table).insert(<String, dynamic>{
        'auth_user_id': authUserId,
        'name': name,
        'email': email,
        'phone': phone,
        'showroom_id': showroomId,
      }).select().single();
      final UserModel model = UserModel.fromJson(SafeJson.asMap(row));
      for (final String roleId in roleIds) {
        await supabase.table('user_roles').insert(<String, dynamic>{
          'user_id': model.id,
          'role_id': roleId,
        });
      }
      return model;
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<UserModel> update(String id, Map<String, dynamic> patch) async {
    try {
      final dynamic row = await supabase
          .table(_table)
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return UserModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Soft disable (users are never physically deleted).
  Future<void> deactivate(String id) async {
    try {
      await supabase
          .table(_table)
          .update(<String, dynamic>{'status': 'inactive'})
          .eq('id', id);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Replaces the role assignments of a user.
  Future<void> setRoles(String userId, List<String> roleIds) async {
    try {
      await supabase.table('user_roles').delete().eq('user_id', userId);
      for (final String roleId in roleIds) {
        await supabase.table('user_roles').insert(<String, dynamic>{
          'user_id': userId,
          'role_id': roleId,
        });
      }
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ---------------------------------------------------------------- roles

  Future<List<RoleModel>> listRoles() async {
    try {
      final dynamic rows =
          await supabase.table('roles').select().order('name');
      return <RoleModel>[
        for (final dynamic r in SafeJson.asList(rows))
          if (r is Map) RoleModel.fromJson(SafeJson.asMap(r)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<List<PermissionModel>> listPermissions() async {
    try {
      final dynamic rows = await supabase
          .table('permissions')
          .select()
          .order('module')
          .order('action');
      return <PermissionModel>[
        for (final dynamic r in SafeJson.asList(rows))
          if (r is Map) PermissionModel.fromJson(SafeJson.asMap(r)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<List<String>> rolePermissionIds(String roleId) async {
    try {
      final dynamic rows = await supabase
          .table('role_permissions')
          .select('permission_id')
          .eq('role_id', roleId);
      return <String>[
        for (final dynamic r in SafeJson.asList(rows))
          if (r is Map) SafeJson.asText(r['permission_id']),
      ].where((String id) => id.isNotEmpty).toList();
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<void> setRolePermissions(
      String roleId, List<String> permissionIds) async {
    try {
      await supabase.table('role_permissions').delete().eq('role_id', roleId);
      for (final String permissionId in permissionIds) {
        await supabase.table('role_permissions').insert(<String, dynamic>{
          'role_id': roleId,
          'permission_id': permissionId,
        });
      }
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  // ------------------------------------------------------- offline sync ops

  /// Applies a queued user mutation (offline create/update/delete).
  Future<SyncOperationResult> applySyncOp(SyncQueueEntry operation) async {
    switch (operation.operation) {
      case SyncOperation.create:
        try {
          final dynamic row = await supabase
              .table(_table)
              .insert(operation.payload)
              .select()
              .single();
          return SyncOperationResult.ok(
            serverId: row is Map ? SafeJson.asId(row['id']) : null,
          );
        } catch (e) {
          return _mapSyncFailure(e);
        }
      case SyncOperation.update:
        try {
          final dynamic row = await supabase
              .table(_table)
              .update(operation.payload)
              .eq('id', operation.entityId)
              .select()
              .maybeSingle();
          if (row == null) {
            return SyncOperationResult.conflictWith(
              'User no longer exists on the server.',
            );
          }
          return SyncOperationResult.ok(
            serverId: operation.entityId,
            serverUpdatedAt: SafeJson.asDate(
                row is Map ? SafeJson.asMap(row)['updated_at'] : null),
          );
        } catch (e) {
          return _mapSyncFailure(e);
        }
      case SyncOperation.delete:
        try {
          await supabase.table(_table).update(<String, dynamic>{
            'status': 'inactive',
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          }).eq('id', operation.entityId);
          return SyncOperationResult.ok(serverId: operation.entityId);
        } catch (e) {
          return _mapSyncFailure(e);
        }
      case SyncOperation.payment:
      case SyncOperation.sale:
      case SyncOperation.service:
        return SyncOperationResult.fail(
            'Unsupported operation for users: ${operation.operation.value}');
    }
  }

  SyncOperationResult _mapSyncFailure(Object e) {
    final AppException mapped = ErrorMapper.map(e);
    if (mapped is ConflictException || mapped is ValidationException) {
      return SyncOperationResult.conflictWith(mapped.message);
    }
    return SyncOperationResult.fail(mapped.message);
  }
}
