import 'dart:async';

import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/features/notifications/models/notification_model.dart';
import 'package:enterprise_bike_showroom/features/notifications/repositories/notification_repository.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';

/// Reactive notification state: badge count, list, read management.
class NotificationController extends GetxController {
  NotificationController({
    required NotificationRepository repository,
    required AppStateController appState,
    required SessionController session,
  })  : repository = repository,
        appState = appState,
        session = session;

  final NotificationRepository repository;
  final AppStateController appState;
  final SessionController session;

  final RxInt unreadCount = 0.obs;
  final RxList<NotificationModel> notifications = <NotificationModel>[].obs;
  final RxBool isLoading = false.obs;
  final Rx<PageInfo> pageInfo = Rx<PageInfo>(PageInfo.empty());

  Timer? _badgeTimer;

  @override
  void onInit() {
    super.onInit();
    refreshBadge();
    // Light polling keeps the badge fresh without a realtime subscription
    // on every screen.
    _badgeTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      refreshBadge();
    });
  }

  /// Refreshes the unread badge count.
  Future<void> refreshBadge() async {
    if (!session.isAuthenticated) {
      unreadCount.value = 0;
      return;
    }
    try {
      final int count = await repository.unreadCount(
        showroomId: session.isSuperAdmin ? null : session.activeShowroomId,
      );
      unreadCount.value = count;
    } catch (e) {
      AppLogger.warning('NOTIFICATIONS', 'badge refresh failed', error: e);
    }
  }

  /// Loads the notifications list (page 1).
  Future<void> load() async {
    await _loadPage(1);
  }

  Future<void> loadMore() async {
    if (!pageInfo.value.hasNext || isLoading.value) return;
    await _loadPage(pageInfo.value.page + 1, append: true);
  }

  Future<void> _loadPage(int page, {bool append = false}) async {
    isLoading.value = true;
    try {
      final PageQuery query = PageQuery(
        page: page,
        pageSize: appState.pageSize.value,
      );
      final PaginatedResponse<NotificationModel> result =
          await repository.list(query);
      if (append) {
        notifications.addAll(result.items);
      } else {
        notifications.assignAll(result.items);
      }
      pageInfo.value = result.info;
    } catch (e) {
      AppLogger.warning('NOTIFICATIONS', 'list load failed', error: e);
    } finally {
      isLoading.value = false;
    }
  }

  /// Marks one notification read and updates the badge.
  Future<void> markRead(String id) async {
    final int index = notifications.indexWhere(
        (NotificationModel n) => n.id == id);
    if (index >= 0 && !notifications[index].isRead) {
      notifications[index] = notifications[index].copyWith(isRead: true);
      final int remaining = unreadCount.value - 1;
      unreadCount.value = remaining < 0 ? 0 : remaining;
    }
    try {
      await repository.markRead(id);
    } catch (e) {
      AppLogger.warning('NOTIFICATIONS', 'markRead failed', error: e);
    }
  }

  /// Marks everything read.
  Future<void> markAllRead() async {
    try {
      await repository.markAllRead();
      for (int i = 0; i < notifications.length; i++) {
        if (!notifications[i].isRead) {
          notifications[i] = notifications[i].copyWith(isRead: true);
        }
      }
      unreadCount.value = 0;
    } catch (e) {
      AppLogger.warning('NOTIFICATIONS', 'markAllRead failed', error: e);
    }
  }

  /// Opens a notification (marks read + navigates to the reference).
  Future<void> open(NotificationModel notification) async {
    final String? nid = notification.id;
    if (!notification.isRead && nid != null) await markRead(nid);
    _navigateToReference(notification);
  }

  void _navigateToReference(NotificationModel notification) {
    final String? type = notification.referenceType;
    if (type == null || notification.referenceId == null) return;
    switch (type) {
      case 'sale':
        Get.toNamed('${AppRoutes.saleDetails}/${notification.referenceId}');
        break;
      case 'invoice':
        Get.toNamed('${AppRoutes.invoiceDetails}/${notification.referenceId}');
        break;
      case 'payment':
        Get.toNamed('${AppRoutes.paymentDetails}/${notification.referenceId}');
        break;
      case 'service':
        Get.toNamed('${AppRoutes.serviceDetails}/${notification.referenceId}');
        break;
      case 'customer':
        Get.toNamed('${AppRoutes.customerDetails}/${notification.referenceId}');
        break;
      case 'loan':
        Get.toNamed('${AppRoutes.loanDetails}/${notification.referenceId}');
        break;
      case 'reminder':
        Get.toNamed(AppRoutes.reminders);
        break;
      default:
        break;
    }
  }

  @override
  void onClose() {
    _badgeTimer?.cancel();
    super.onClose();
  }
}
