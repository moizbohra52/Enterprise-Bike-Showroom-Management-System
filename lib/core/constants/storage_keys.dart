/// SharedPreferences keys. Only lightweight, non-sensitive preferences are
/// stored here (theme, language, selected showroom, onboarding, table prefs).
class StorageKeys {
  StorageKeys._();

  static const String themeMode = 'theme_mode';
  static const String accentColor = 'accent_color';
  static const String language = 'language';
  static const String selectedShowroomId = 'selected_showroom_id';
  static const String onboardingComplete = 'onboarding_complete';
  static const String pageSize = 'table_page_size';
  static const String taxRate = 'default_tax_rate';
  static const String filterPreferences = 'filter_preferences';
  static const String lastDashboardWidgets = 'last_dashboard_widgets';
  static const String fcmPushEnabled = 'fcm_push_enabled';
}

/// Hive box names for the local (offline) database.
class HiveBoxNames {
  HiveBoxNames._();

  /// General JSON cache (read-through cache for lists & entities).
  static const String cache = 'app_cache';

  /// Draft transactions saved while offline.
  static const String drafts = 'app_drafts';

  /// Pending synchronization operations.
  static const String syncQueue = 'app_sync_queue';
}
