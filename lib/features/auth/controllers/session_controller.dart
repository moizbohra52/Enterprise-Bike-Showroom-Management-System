import 'dart:async';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthEvent, AuthState;

import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/common/models/role_model.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/common/models/user_model.dart';
import 'package:enterprise_bike_showroom/common/services/permission_service.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/features/users/repositories/user_repository.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';
import 'package:enterprise_bike_showroom/services/notification_service.dart';

/// Owns the authenticated session: current user, roles, permissions,
/// accessible showrooms and the active (working) showroom.
///
/// All permission checks in the app go through [can].
class SessionController extends GetxController {
  SessionController({
    required AuthService authService,
    required UserRepository userRepository,
    required AppStateController appState,
    NotificationService? notificationService,
  })  : authService = authService,
        userRepository = userRepository,
        appState = appState,
        notificationService = notificationService;

  final AuthService authService;
  final UserRepository userRepository;
  final AppStateController appState;
  final NotificationService? notificationService;

  final Rx<UserModel?> user = Rx<UserModel?>(null);
  final RxBool isAuthReady = false.obs;
  final RxBool profileLoading = false.obs;

  /// Auth-state subscription (created by [bootstrap]).
  StreamSubscription<AuthState>? _authSubscription;

  bool get isAuthenticated => user.value != null;
  bool get isSuperAdmin => user.value?.isSuperAdmin ?? false;
  List<String> get permissions => user.value?.permissions ?? const <String>[];
  List<String> get roleNames =>
      (user.value?.roles ?? const <RoleModel>[])
          .map((RoleModel r) => r.name)
          .toList(growable: false);

  String get displayName =>
      user.value?.name.isNotEmpty == true ? user.value!.name : 'User';
  String? get displayEmail => user.value?.email;

  /// Showrooms the current user may work in.
  List<ShowroomModel> get accessibleShowrooms =>
      user.value?.showrooms ?? const <ShowroomModel>[];

  /// Id of the currently selected (working) showroom.
  String get activeShowroomId => appState.activeShowroomId.value;

  /// Default GST rate for new sales (persisted app state).
  num get taxRate => appState.taxRate.value;

  Future<void> setTaxRate(num rate) => appState.setTaxRate(rate.toDouble());

  /// The selected showroom object (or the first accessible one).
  ShowroomModel? get activeShowroom {
    final List<ShowroomModel> all = accessibleShowrooms;
    if (all.isEmpty) return null;
    for (final ShowroomModel s in all) {
      if (s.id == activeShowroomId) return s;
    }
    return all.first;
  }

  /// True when the session has at least one showroom.
  bool get hasShowroom => accessibleShowrooms.isNotEmpty;

  /// Permission check used by UI, navigation and route guards.
  ///
  /// SUPER ADMIN implicitly holds every permission.
  bool can(String permission) {
    if (isSuperAdmin) return true;
    return PermissionService.hasExact(permissions, permission);
  }

  /// Module-level convenience: does the user have `module.action`?
  bool canModule(String module, String action) =>
      can(Permissions.of(module, action));

  /// Bootstraps the session after app start:
  /// - watches auth state (login/logout/refresh)
  /// - loads the profile when a session exists
  Future<void> bootstrap() async {
    _authSubscription ??=
        authService.authChanges.listen(_onAuthStateChanged);
    if (authService.hasSession) {
      await _loadProfile();
    } else {
      user.value = null;
      isAuthReady.value = true;
    }
  }

  Future<void> _onAuthStateChanged(AuthState state) async {
    switch (state.eventName) {
      case AuthEvent.signedIn:
        // Push registration must never block the profile load.
        try {
          await notificationService?.registerToken(
            userId: state.session?.user?.id ?? '',
          );
        } catch (e) {
          AppLogger.warning('SESSION', 'push token registration failed',
              error: e);
        }
        await _loadProfile();
      case AuthEvent.signedOut:
        await _clearSession();
      case AuthEvent.tokenRefreshed:
      case AuthEvent.initialSession:
        // No profile reload needed; tokens rotate transparently.
      case AuthEvent.userUpdated:
        await _loadProfile();
    }
  }

  /// Loads the profile (user + roles + permissions + showrooms).
  Future<void> loadProfile() async {
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!authService.hasSession) {
      isAuthReady.value = true;
      return;
    }
    profileLoading.value = true;
    try {
      final UserModel? profile = await userRepository.currentProfile();
      if (profile == null) {
        // Authenticated but no application profile yet (onboarding).
        user.value = null;
        isAuthReady.value = true;
        return;
      }
      user.value = profile;
      // Pick the working showroom (persisted selection or first).
      final String preferred = appState.activeShowroomId.value;
      final bool known = profile.showrooms
          .any((dynamic s) => s.id == preferred);
      if (!known && profile.showrooms.isNotEmpty) {
        await appState.setActiveShowroom(profile.showrooms.first.id!);
      }
      isAuthReady.value = true;
    } on AppException catch (e) {
      AppLogger.error('SESSION', 'profile load failed', error: e);
      isAuthReady.value = true;
    } catch (e) {
      AppLogger.error('SESSION', 'profile load failed',
          error: ErrorMapper.map(e));
      isAuthReady.value = true;
    } finally {
      profileLoading.value = false;
    }
  }

  /// Switches the working showroom (must be in the accessible list).
  Future<void> setActiveShowroom(String showroomId) async {
    if (!accessibleShowrooms.any((ShowroomModel s) => s.id == showroomId)) {
      throw ForbiddenException('You are not assigned to that showroom.');
    }
    await appState.setActiveShowroom(showroomId);
  }

  /// Clears the session state and returns to login.
  Future<void> clearSession() async {
    await _clearSession();
  }

  Future<void> _clearSession() async {
    user.value = null;
    isAuthReady.value = true;
    if (!Get.isRegistered<SessionController>()) return;
    if (Get.currentRoute != AppRoutes.login) {
      Get.offAllNamed(AppRoutes.login);
    }
  }

  /// Navigates to the home (dashboard) once authenticated.
  void goHome() {
    if (isAuthenticated) {
      Get.offAllNamed(AppRoutes.dashboard);
    }
  }

  /// Guards: allows navigation only for authenticated users.
  bool guardAuth() {
    if (!isAuthReady.value) return true; // still bootstrapping
    if (isAuthenticated) return true;
    Get.offAllNamed(AppRoutes.login);
    return false;
  }

  /// Guards: allows navigation only when [permission] is held.
  bool guardPermission(String permission) {
    if (!guardAuth()) return false;
    if (can(permission)) return true;
    Get.offAllNamed(AppRoutes.forbidden);
    return false;
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    super.onClose();
  }
}
