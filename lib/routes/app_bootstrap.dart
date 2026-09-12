import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_messaging/firebase_messaging.dart'
    show RemoteMessage;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/common/controllers/sync_state_controller.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/core/constants/entity_constants.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/customers/repositories/customer_repository.dart';
import 'package:enterprise_bike_showroom/features/inventory/repositories/inventory_repository.dart';
import 'package:enterprise_bike_showroom/features/notifications/controllers/notification_controller.dart';
import 'package:enterprise_bike_showroom/features/notifications/repositories/notification_repository.dart';
import 'package:enterprise_bike_showroom/features/products/repositories/product_repository.dart';
import 'package:enterprise_bike_showroom/features/search/controllers/search_controller.dart';
import 'package:enterprise_bike_showroom/features/search/repositories/search_repository.dart';
import 'package:enterprise_bike_showroom/features/showroom/repositories/showroom_repository.dart';
import 'package:enterprise_bike_showroom/features/users/repositories/user_repository.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/api_service.dart';
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

/// Application bootstrap: infrastructure + the global dependency graph.
///
/// Everything registered here is a *permanent* singleton (services, app state,
/// session, cross-cutting controllers). Feature repositories/controllers stay
/// route-scoped in their own `Bindings`.
class AppBootstrap {
  AppBootstrap._();

  static bool _started = false;
  static bool _backendReady = false;

  /// True when a real Supabase project was reached during startup.
  static bool get isBackendReady => _backendReady;

  /// Runs all startup work. Awaits everything the first frame depends on
  /// (preferences, local boxes, Supabase init, session restore).
  static Future<void> init() async {
    if (_started) return;
    _started = true;
    final DateTime t0 = DateTime.now();

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await Hive.initFlutter();
    final LocalDatabaseService local = LocalDatabaseService();
    await local.init();

    _backendReady = await _initBackend();
    await _initMessaging();

    await _register(prefs: prefs, local: local);

    AppLogger.info(
      'BOOTSTRAP',
      'ready in ${DateTime.now().difference(t0).inMilliseconds}ms '
      '(${EnvironmentConfig.environmentLabel}, '
      'backend: ${_backendReady ? 'configured' : 'placeholder'})',
    );
  }

  /// Supabase init. Placeholder credentials (fresh clone, no `--dart-define`)
  /// keep the app bootable in offline mode instead of crashing.
  static Future<bool> _initBackend() async {
    if (EnvironmentConfig.isPlaceholderBackend) {
      AppLogger.warning(
        'BOOTSTRAP',
        'SUPABASE_URL / SUPABASE_ANON_KEY not provided - running in offline '
        'mode (writes are queued locally).',
      );
      return false;
    }
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
        debug: EnvironmentConfig.isDevelopment,
      );
      return true;
    } catch (e) {
      AppLogger.error('BOOTSTRAP', 'Supabase initialization failed', error: e);
      return false;
    }
  }

  /// Firebase is optional: without native config files push stays disabled.
  static Future<void> _initMessaging() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      AppLogger.info('BOOTSTRAP', 'Firebase initialized (push available)');
    } catch (e) {
      AppLogger.debug(
        'BOOTSTRAP',
        'Firebase not configured; push notifications disabled',
        error: e,
      );
    }
  }

  static Future<void> _register({
    required SharedPreferences prefs,
    required LocalDatabaseService local,
  }) async {
    final SupabaseService supabase =
        Get.put<SupabaseService>(SupabaseService(), permanent: true);
    Get.put<LocalDatabaseService>(local, permanent: true);

    final ConnectivityService connectivity = Get.put<ConnectivityService>(
      ConnectivityService(),
      permanent: true,
    );
    connectivity.init();

    final AuthService auth =
        Get.put<AuthService>(AuthService(), permanent: true);
    if (_backendReady) auth.init();

    final ApiService api =
        Get.put<ApiService>(ApiService(), permanent: true);
    await api.init(tokenProvider: () => _backendReady ? auth.currentAccessToken : null);

    final PdfService pdf = Get.put<PdfService>(PdfService(), permanent: true);
    Get.put<ExportService>(ExportService(pdf: pdf), permanent: true);
    final StorageService storage =
        Get.put<StorageService>(StorageService(), permanent: true);
    Get.put<ImageService>(
      ImageService(storage: storage),
      permanent: true,
    );

    final NotificationService push = Get.put<NotificationService>(
      NotificationService(supabase: supabase),
      permanent: true,
    );
    push.onMessageOpened = _onPushOpened;
    push.onForegroundMessage = _onPushForeground;
    await push.init();

    final AppStateController appState =
        Get.put<AppStateController>(AppStateController(prefs), permanent: true);
    await appState.load();

    // Offline -> online synchronization engine.
    final SyncService sync = Get.put<SyncService>(
      SyncService(local: local, connectivity: connectivity),
      permanent: true,
    );
    _registerSyncHandlers(sync, supabase, local);
    sync.start();
    Get.put<SyncStateController>(
      SyncStateController(sync),
      permanent: true,
    );

    // Session: auth state -> profile -> roles/permissions -> showroom.
    final UserRepository users =
        Get.put<UserRepository>(UserRepository(supabase), permanent: true);
    final SessionController session = Get.put<SessionController>(
      SessionController(
        authService: auth,
        userRepository: users,
        appState: appState,
        notificationService: push,
      ),
      permanent: true,
    );
    // Profile restore needs a live Supabase client; without it the session
    // stays unauthenticated and the splash routes to login.
    if (_backendReady) {
      await session.bootstrap();
    }

    // Cross-cutting controllers used by the app shell (any route).
    Get.put<SearchRepository>(SearchRepository(supabase), permanent: true);
    Get.put<GlobalSearchController>(
      GlobalSearchController(Get.find<SearchRepository>()),
      permanent: true,
    );
    Get.put<NotificationRepository>(
      NotificationRepository(supabase),
      permanent: true,
    );
    Get.put<NotificationController>(
      NotificationController(
        repository: Get.find<NotificationRepository>(),
        appState: appState,
        session: session,
      ),
      permanent: true,
    );
  }

  /// Queued writes are applied by the repository that owns each entity table.
  static void _registerSyncHandlers(
    SyncService sync,
    SupabaseService supabase,
    LocalDatabaseService local,
  ) {
    final ShowroomRepository showrooms = ShowroomRepository(supabase);
    final UserRepository users = UserRepository(supabase);
    final ProductRepository products = ProductRepository(supabase);
    final InventoryRepository inventory = InventoryRepository(supabase);
    final CustomerRepository customers = CustomerRepository(supabase, local);

    sync
      ..registerHandler(
        EntityType.showroom,
        showrooms.applySyncOp,
      )
      ..registerHandler(EntityType.user, users.applySyncOp)
      ..registerHandler(EntityType.product, products.applySyncOp)
      ..registerHandler(EntityType.inventory, inventory.applySyncOp)
      ..registerHandler(EntityType.customer, customers.applySyncOp);
  }

  /// Notification taps open the notification centre (unless already there).
  static void _onPushOpened(RemoteMessage message) {
    if (Get.currentRoute == AppRoutes.notifications) return;
    Get.toNamed(AppRoutes.notifications);
  }

  /// Foreground pushes refresh the badge immediately.
  static void _onPushForeground(RemoteMessage message) {
    if (!Get.isRegistered<NotificationController>()) return;
    Get.find<NotificationController>().refreshBadge();
  }

  /// Resets the bootstrap flags (used by tests and hot-restart flows).
  @visibleForTesting
  static void resetForTests() {
    _started = false;
    _backendReady = false;
  }
}
