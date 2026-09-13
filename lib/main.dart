import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/routes/app_pages.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/routes/initial_binding.dart';
import 'package:enterprise_bike_showroom/services/local_database_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

/// Application entry point.
///
/// Boot order matters:
/// 1. Flutter bindings + logging
/// 2. `SharedPreferences` (persisted preferences)
/// 3. Hive (offline cache / drafts / sync queue)
/// 4. Supabase (auth + PostgREST + storage) — placeholder-safe
/// 5. Firebase (push) — optional, never fatal
/// 6. [AppStateController] (theme, language, active showroom)
///
/// Everything else (services, session, feature controllers) is wired by
/// [InitialBinding] when the router starts.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init();
  AppLogger.info(
    'BOOT',
    '${AppConfig.appName} ${AppConfig.appVersion} '
    '(${EnvironmentConfig.environmentLabel})',
  );

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await Hive.initFlutter();

  final LocalDatabaseService localDb = LocalDatabaseService();
  await localDb.init();
  Get.put<LocalDatabaseService>(localDb, permanent: true);

  await _initSupabase();
  await _initFirebase();

  final AppStateController appState = Get.put<AppStateController>(
    AppStateController(prefs),
    permanent: true,
  );
  await appState.load();

  runApp(const EnterpriseShowroomApp());
}

/// Connects the Supabase client.
///
/// Development builds fall back to placeholder credentials so the UI still
/// runs (every remote call then fails with a mapped [AppException] instead of
/// crashing the app). Staging/production builds throw unless real values are
/// supplied with `--dart-define`.
Future<void> _initSupabase() async {
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    if (EnvironmentConfig.isPlaceholderBackend) {
      AppLogger.warning(
        'BOOT',
        'Supabase is using placeholder credentials. Build with '
        '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
  } catch (e) {
    AppLogger.critical('BOOT', 'Supabase initialization failed', error: e);
  }
}

/// Initializes Firebase Cloud Messaging when platform config is present.
///
/// Push is an enhancement, never a hard dependency: failures are logged and
/// [NotificationService.init] degrades to in-app notifications only.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
    AppLogger.info('BOOT', 'firebase initialized');
  } catch (e) {
    AppLogger.warning('BOOT', 'Firebase unavailable; push disabled', error: e);
  }
}

/// Root widget.
///
/// Rebuilds the [GetMaterialApp] when theme mode or language changes so the
/// whole tree follows the persisted preferences.
class EnterpriseShowroomApp extends StatelessWidget {
  const EnterpriseShowroomApp({super.key});

  @override
  Widget build(BuildContext context) {
    final AppStateController appState = Get.find<AppStateController>();
    return Obx(
      () => GetMaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        initialBinding: InitialBinding(),
        initialRoute: AppRoutes.splash,
        getPages: AppPages.pages,
        defaultTransition: Transition.fadeIn,
        theme: appState.lightTheme,
        darkTheme: appState.darkTheme,
        themeMode: appState.themeMode.value,
        locale: Locale(appState.language.value),
        fallbackLocale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('en'), Locale('hi')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
