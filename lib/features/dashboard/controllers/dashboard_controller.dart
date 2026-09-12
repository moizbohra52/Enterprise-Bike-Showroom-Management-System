import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/dashboard/repositories/dashboard_repository.dart';

/// Loads and holds the dashboard snapshot for the active showroom.
///
/// The snapshot is scoped to the working showroom; switching showrooms in the
/// top bar refreshes it automatically.
class DashboardController extends GetxController {
  DashboardController({
    required DashboardRepository repository,
    required SessionController session,
  })  : repository = repository,
        session = session;

  final DashboardRepository repository;
  final SessionController session;

  final Rx<DashboardSnapshot?> snapshot = Rx<DashboardSnapshot?>(null);
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final Rx<DateTime?> loadedAt = Rx<DateTime?>(null);

  Worker? _showroomWorker;

  /// Showroom filter (null = all showrooms the user can see).
  String? get showroomId {
    final String id = session.activeShowroomId;
    return id.isEmpty ? null : id;
  }

  DashboardSnapshot? get data => snapshot.value;

  bool get hasData => snapshot.value != null;

  @override
  void onInit() {
    super.onInit();
    refresh();
    // Switching the working showroom re-scopes every widget.
    _showroomWorker = ever<String>(
      session.appState.activeShowroomId,
      (String _) => refresh(),
    );
  }

  @override
  void onClose() {
    _showroomWorker?.dispose();
    super.onClose();
  }

  /// Reloads all widgets (safe to call while loading: it is ignored).
  Future<void> refresh() async {
    if (isLoading.value) return;
    isLoading.value = true;
    error.value = '';
    try {
      snapshot.value = await repository.load(showroomId: showroomId);
      loadedAt.value = DateTime.now();
    } on AppException catch (e) {
      error.value = e.message;
    } catch (e) {
      error.value = ErrorMapper.friendly(e);
    } finally {
      isLoading.value = false;
    }
  }

  /// Clears cached numbers (used after a bulk import or logout).
  void clear() {
    snapshot.value = null;
    loadedAt.value = null;
    error.value = '';
  }
}
