import 'dart:async';

import 'package:enterprise_bike_showroom/common/models/user_model.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/users/repositories/user_repository.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:get/get.dart';

/// Users & roles administration list.
///
/// Owns its own pagination state (rather than [BaseListController]) because
/// `UserRepository.list` returns the exact total with the page, which the
/// generic loader signature cannot carry.
class UsersController extends GetxController {
  UsersController(this.repository, this.session);

  final UserRepository repository;
  final SessionController session;

  final RxList<UserModel> items = <UserModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;
  final Rx<PageInfo> pageInfo = Rx<PageInfo>(PageInfo.empty());

  /// Debounced search text (bound to `AppSearchField`).
  final RxString search = ''.obs;
  final RxString statusFilter = ''.obs;
  final RxString showroomFilter = ''.obs;
  final RxString sortField = 'created_at'.obs;
  final RxBool sortAscending = false.obs;

  int _page = 1;
  int _pageSize = AppConfig.defaultPageSize;
  Timer? _searchTimer;

  bool get canCreate => session.can(Permissions.usersCreate);
  bool get canEdit => session.can(Permissions.usersEdit);
  bool get canDelete => session.can(Permissions.usersDelete);

  @override
  void onInit() {
    super.onInit();
    refresh();
  }

  @override
  void onClose() {
    _searchTimer?.cancel();
    super.onClose();
  }

  Future<void> refresh() async {
    _page = 1;
    await _load();
  }

  Future<void> goToPage(int page) async {
    if (page < 1) return;
    _page = page;
    await _load();
  }

  Future<void> setPageSize(int size) async {
    _pageSize = size;
    _page = 1;
    await _load();
  }

  void updateSearch(String value) {
    search.value = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: AppConfig.searchDebounceMs),
      () {
        _page = 1;
        unawaited(_load());
      },
    );
  }

  Future<void> setStatusFilter(String? value) async {
    statusFilter.value = value ?? '';
    await refresh();
  }

  Future<void> setShowroomFilter(String? value) async {
    showroomFilter.value = value ?? '';
    await refresh();
  }

  Future<void> setSort(String field, bool ascending) async {
    sortField.value = field;
    sortAscending.value = ascending;
    await refresh();
  }

  Future<void> clearFilters() async {
    search.value = '';
    statusFilter.value = '';
    showroomFilter.value = '';
    await refresh();
  }

  Future<void> _load() async {
    if (isLoading.value) return;
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final PageQuery query = PageQuery(
        page: _page,
        pageSize: _pageSize,
        search: search.value.trim().isEmpty ? null : search.value.trim(),
        filters: <String, dynamic>{
          if (statusFilter.value.isNotEmpty) 'status': statusFilter.value,
          if (showroomFilter.value.isNotEmpty)
            'showroom_id': showroomFilter.value,
        },
        orderBy: sortField.value,
        ascending: sortAscending.value,
      );
      final PaginatedResponse<UserModel> response =
          await repository.list(query);
      items.assignAll(response.items);
      pageInfo.value = response.info;
    } on AppException catch (e) {
      errorMessage.value = e.message;
      AppLogger.error('USERS', e.message, error: e.details);
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      AppLogger.error('USERS', 'list failed', error: e);
    } finally {
      isLoading.value = false;
    }
  }

  /// Opens the create/edit form, then reloads on return.
  Future<void> openForm({String? id}) async {
    await Get.toNamed(
      AppRoutes.userForm,
      parameters: <String, String?>{
        if (id != null) 'id': id,
      },
    );
    await refresh();
  }

  Future<void> openDetails(UserModel user) async {
    await Get.toNamed(
      AppRoutes.userDetails,
      parameters: <String, String?>{'id': user.id},
    );
    await refresh();
  }

  /// Soft-disables a user (never physically deleted).
  Future<void> deactivate(UserModel user) async {
    final String? id = user.id;
    if (id == null) return;
    try {
      await repository.deactivate(id);
      await refresh();
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
    }
  }

  Future<void> reactivate(UserModel user) async {
    final String? id = user.id;
    if (id == null) return;
    try {
      await repository.update(id, <String, dynamic>{'status': 'active'});
      await refresh();
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
    }
  }
}
