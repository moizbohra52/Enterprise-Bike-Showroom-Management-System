import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/common/controllers/sync_state_controller.dart';
import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/core/constants/entity_constants.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/repositories/customer_repository.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/notifications/controllers/notification_controller.dart';
import 'package:enterprise_bike_showroom/features/notifications/repositories/notification_repository.dart';
import 'package:enterprise_bike_showroom/features/search/controllers/search_controller.dart';
import 'package:enterprise_bike_showroom/features/search/repositories/search_repository.dart';
import 'package:enterprise_bike_showroom/features/users/repositories/user_repository.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';
import 'package:enterprise_bike_showroom/services/connectivity_service.dart';
import 'package:enterprise_bike_showroom/services/export_service.dart';
import 'package:enterprise_bike_showroom/services/image_service.dart';
import 'package:enterprise_bike_showroom/services/local_database_service.dart';
import 'package:enterprise_bike_showroom/services/notification_service.dart';
import 'package:enterprise_bike_showroom/services/pdf_service.dart';
import 'package:enterprise_bike_showroom/services/storage_service.dart';
import 'package:enterprise_bike_showroom/services/supabase_service.dart';
import 'package:enterprise_bike_showroom/services/sync_service.dart';
import 'package:get/get.dart';

/// Global dependency graph, wired once when the router starts.
///
/// Registered permanently because the app shell (`TopBar`, `SidebarMenu`) and
/// every feature page depend on the session, connectivity and sync state.
class InitialBinding extends Bindings {
  @override
  void dependencies() {
    _registerServices();
    _registerRepositories();
    _registerControllers();
  }

  void _registerServices() {
    Get.put<SupabaseService>(SupabaseService(), permanent: true);

    final AuthService auth =
        Get.put<AuthService>(AuthService(), permanent: true);
    auth.init();

    final ConnectivityService connectivity =
        Get.put<ConnectivityService>(ConnectivityService(), permanent: true);
    connectivity.init();

    // Opened in `main()` before `runApp`; reused when present (tests).
    final LocalDatabaseService local =
        Get.isRegistered<LocalDatabaseService>()
            ? Get.find<LocalDatabaseService>()
            : Get.put<LocalDatabaseService>(
                LocalDatabaseService(),
                permanent: true,
              );

    Get.put<SyncService>(
      SyncService(local: local, connectivity: connectivity),
      permanent: true,
    );

    final NotificationService notifications = Get.put<NotificationService>(
      NotificationService(supabase: Get.find<SupabaseService>()),
      permanent: true,
    );
    notifications.init();

    final StorageService storage =
        Get.put<StorageService>(StorageService(), permanent: true);

    // Stateless pipelines shared by several modules. They are `Get.find`-ed
    // from invoice/payment/service views (PDF print), the report screen
    // (CSV/Excel/PDF export) and the upload sheets, so they must be global.
    final PdfService pdf = Get.put<PdfService>(PdfService(), permanent: true);
    Get.put<ExportService>(ExportService(pdf: pdf), permanent: true);
    Get.put<ImageService>(
      ImageService(storage: storage),
      permanent: true,
    );
  }

  void _registerRepositories() {
    final SupabaseService supabase = Get.find<SupabaseService>();
    Get.put<UserRepository>(UserRepository(supabase), permanent: true);
    Get.put<NotificationRepository>(
      NotificationRepository(supabase),
      permanent: true,
    );
    Get.put<SearchRepository>(SearchRepository(supabase), permanent: true);

    // Offline queue appliers. Today the customer and user flows are the ones
    // that enqueue writes (`*_controller` -> `SyncService.enqueue`); any
    // entity type without a handler is flagged as a conflict by SyncService.
    final SyncService sync = Get.find<SyncService>();
    sync.registerHandler(
      EntityType.user,
      Get.find<UserRepository>().applySyncOp,
    );
    final CustomerRepository customers = Get.put<CustomerRepository>(
      CustomerRepository(supabase, Get.find<LocalDatabaseService>()),
      permanent: true,
    );
    sync.registerHandler(EntityType.customer, customers.applySyncOp);
  }

  void _registerControllers() {
    final SessionController session = Get.put<SessionController>(
      SessionController(
        authService: Get.find<AuthService>(),
        userRepository: Get.find<UserRepository>(),
        appState: Get.find<AppStateController>(),
        notificationService: Get.find<NotificationService>(),
      ),
      permanent: true,
    );
    session.bootstrap();

    Get.put<AuthController>(
      AuthController(Get.find<AuthService>()),
      permanent: true,
    );
    Get.put<SyncStateController>(
      SyncStateController(Get.find<SyncService>()),
      permanent: true,
    );
    Get.put<NotificationController>(
      NotificationController(
        repository: Get.find<NotificationRepository>(),
        appState: Get.find<AppStateController>(),
        session: session,
      ),
      permanent: true,
    );
    Get.put<GlobalSearchController>(
      GlobalSearchController(Get.find<SearchRepository>()),
      permanent: true,
    );
  }
}
