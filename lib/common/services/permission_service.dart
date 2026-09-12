import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';

/// Pure permission evaluation (mirrors the server-side `has_permission()`).
///
/// Supported grants (in order):
/// - exact `module.action`
/// - module wildcard `module.*`
/// - global wildcard `*.*` (SUPER ADMIN)
class PermissionService {
  PermissionService._();

  /// True when [permissions] grant [module].[action].
  static bool has(
    Iterable<String> permissions,
    String module,
    String action,
  ) {
    if (permissions.isEmpty) return false;
    final String exact = Permissions.of(module, action);
    final String wildcard = Permissions.moduleWildcard(module);
    for (final String grant in permissions) {
      if (grant == exact ||
          grant == wildcard ||
          grant == Permissions.all) {
        return true;
      }
    }
    return false;
  }

  /// Convenience for a full `module.action` string.
  static bool hasExact(Iterable<String> permissions, String permission) {
    if (permission == Permissions.all) return true;
    final List<String> parts = permission.split('.');
    if (parts.length != 2) return false;
    return has(permissions, parts[0], parts[1]);
  }
}
