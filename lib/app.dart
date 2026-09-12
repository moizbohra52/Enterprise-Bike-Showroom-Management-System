import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/app_state_controller.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/routes/app_pages.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Root widget: theme + routing + localization.
///
/// All services and global controllers are already registered by
/// `AppBootstrap.init()` (see `main.dart`), so nothing is initialized here.
class EnterpriseBikeApp extends GetView<AppStateController> {
  const EnterpriseBikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ThemeMode mode = controller.themeMode.value;
      return GetMaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: EnvironmentConfig.isDevelopment,
        themeMode: mode,
        theme: controller.lightTheme.value,
        darkTheme: controller.darkTheme.value,
        locale: Locale(controller.language.value),
        supportedLocales: const <Locale>[Locale('en'), Locale('hi')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: AppRoutes.splash,
        getPages: AppPages.pages,
        unknownRoute: AppPages.unknownRoute,
        defaultTransition: Transition.fadeIn,
        transitionDuration: const Duration(milliseconds: 220),
        // Data-dense grids stay legible on OS text scaling.
        builder: (BuildContext context, Widget? child) {
          final MediaQueryData media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.3,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      );
    });
  }
}
