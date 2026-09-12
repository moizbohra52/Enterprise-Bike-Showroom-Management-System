import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/services/sync_service.dart';

/// GetX-reactive mirror of [SyncService] state for the UI (badges, banners).
class SyncStateController extends GetxController {
  SyncStateController(this.sync);

  final SyncService sync;

  final RxInt pendingCount = 0.obs;
  final RxInt conflictCount = 0.obs;
  final RxBool isSyncing = false.obs;
  final Rx<DateTime?> lastSyncAt = Rx<DateTime?>(null);
  final RxString lastError = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _sync();
    sync.addListener(_onQueueChanged);
  }

  void _onQueueChanged(SyncService service) => _sync();

  void _sync() {
    pendingCount.value = sync.pendingCount;
    conflictCount.value = sync.conflictCount;
    isSyncing.value = sync.isSyncing;
    lastSyncAt.value = sync.lastSyncAt;
    lastError.value = sync.lastError ?? '';
  }

  /// Triggers a sync run (respects connectivity).
  Future<void> syncNow() async {
    isSyncing.value = true;
    try {
      await sync.syncNow();
    } finally {
      _sync();
    }
  }

  @override
  void onClose() {
    sync.removeListener(_onQueueChanged);
    super.onClose();
  }
}
