import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/core/constants/storage_keys.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';

/// Global, lightweight app state persisted in SharedPreferences:
/// theme, accent, language, selected showroom, onboarding, page size.
class AppStateController extends GetxController {
  AppStateController(this.prefs);

  final SharedPreferences prefs;

  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;
  final Rx<String> language = 'en'.obs;
  final Rx<String> activeShowroomId = ''.obs;
  final RxInt pageSize = RxInt(AppConfig.defaultPageSize);
  final RxBool onboardingComplete = false.obs;

  /// Default GST rate applied to new sales (editable by admins).
  final RxDouble taxRate = AppConfig.defaultTaxRate.obs;

  /// Push notifications toggle (device-level preference).
  final RxBool notificationsEnabled = true.obs;

  /// Theme data cache (rebuilt on accent change).
  ThemeData lightTheme = AppTheme.light();
  ThemeData darkTheme = AppTheme.dark();

  /// Loads persisted preferences.
  Future<void> load() async {
    try {
      final String? theme = prefs.getString(StorageKeys.themeMode);
      themeMode.value = theme == null
          ? ThemeMode.system
          : ThemeMode.values.firstWhere(
                (ThemeMode m) => m.name == theme,
                orElse: () => ThemeMode.system,
              );
      language.value = prefs.getString(StorageKeys.language) ?? 'en';
      activeShowroomId.value = prefs.getString(StorageKeys.selectedShowroomId) ?? '';
      pageSize.value = prefs.getInt(StorageKeys.pageSize) ?? AppConfig.defaultPageSize;
      onboardingComplete.value =
          prefs.getBool(StorageKeys.onboardingComplete) ?? false;
      taxRate.value = prefs.getDouble(StorageKeys.taxRate) ?? AppConfig.defaultTaxRate;
      notificationsEnabled.value =
          prefs.getBool(StorageKeys.fcmPushEnabled) ?? true;
      final int? accent = prefs.getInt(StorageKeys.accentColor);
      _applyAccent(accent);
    } catch (e) {
      AppLogger.warning('STATE', 'preference load failed', error: e);
    }
  }

  /// Sets + persists the theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await prefs.setString(StorageKeys.themeMode, mode.name);
  }

  /// Sets + persists a custom accent (MaterialColor seed).
  Future<void> setAccent(MaterialColor accent) async {
    _applyAccent(accent.value);
    await prefs.setInt(StorageKeys.accentColor, accent.value);
  }

  void _applyAccent(int? accentValue) {
    if (accentValue == null) {
      lightTheme = AppTheme.light();
      darkTheme = AppTheme.dark();
      return;
    }
    final MaterialColor accent = MaterialColor(accentValue, <int, Color>{
      50: Color(accentValue).withAlpha(30),
      100: Color(accentValue).withAlpha(60),
      200: Color(accentValue).withAlpha(100),
      300: Color(accentValue).withAlpha(160),
      400: Color(accentValue).withAlpha(200),
      500: Color(accentValue),
      600: Color(accentValue),
      700: Color(accentValue),
      800: Color(accentValue).withAlpha(230),
      900: Color(accentValue).withAlpha(250),
    });
    lightTheme = AppTheme.light(accent: accent);
    darkTheme = AppTheme.dark(accent: accent);
  }

  /// Sets + persists the language code.
  Future<void> setLanguage(String code) async {
    language.value = code;
    await prefs.setString(StorageKeys.language, code);
  }

  /// Sets + persists the selected (working) showroom.
  Future<void> setActiveShowroom(String showroomId) async {
    activeShowroomId.value = showroomId;
    await prefs.setString(StorageKeys.selectedShowroomId, showroomId);
  }

  /// Sets + persists the grid page size.
  Future<void> setPageSize(int size) async {
    pageSize.value = size;
    await prefs.setInt(StorageKeys.pageSize, size);
  }

  /// Marks onboarding complete.
  Future<void> completeOnboarding() async {
    onboardingComplete.value = true;
    await prefs.setBool(StorageKeys.onboardingComplete, true);
  }

  /// Sets + persists the default tax rate.
  Future<void> setTaxRate(double rate) async {
    taxRate.value = rate;
    await prefs.setDouble(StorageKeys.taxRate, rate);
  }

  /// Sets + persists the push-notification preference.
  Future<void> setNotificationsEnabled(bool enabled) async {
    notificationsEnabled.value = enabled;
    await prefs.setBool(StorageKeys.fcmPushEnabled, enabled);
  }
}
