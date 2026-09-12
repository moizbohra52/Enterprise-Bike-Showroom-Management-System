/// Global, non-secret application constants.
///
/// Everything that is an application-wide policy (page sizes, breakpoints,
/// thresholds, timeouts) lives here so feature code never hardcodes values.
class AppConfig {
  AppConfig._();

  /// Display name of the application.
  static const String appName = 'Enterprise Bike Showroom';

  /// Marketing/legal version shown in Settings and About dialogs.
  static const String appVersion = '1.0.0';

  /// Build number (kept in sync with pubspec `version`).
  static const int appBuildNumber = 1;

  /// Default number of rows returned by paginated list queries.
  static const int defaultPageSize = 20;

  /// Page sizes offered by [AppPagination].
  static const List<int> pageSizeOptions = <int>[20, 50, 100];

  /// Debounce window for search fields (milliseconds).
  static const int searchDebounceMs = 400;

  /// Default HTTP timeout for Dio requests.
  static const Duration apiTimeout = Duration(seconds: 30);

  /// Maximum automatic retry attempts for idempotent requests.
  static const int maxRetryAttempts = 3;

  /// Width (logical px) above which the desktop layout (sidebar + data grid)
  /// is used.
  static const double desktopBreakpoint = 900.0;

  /// Width (logical px) above which the tablet layout is used.
  static const double tabletBreakpoint = 600.0;

  /// Number of free services generated for a sold vehicle by default.
  static const int freeServiceDefaultCount = 4;

  /// Inventory count at or below which a product is considered "low stock".
  static const int lowStockThreshold = 5;

  /// Days before insurance expiry at which reminders start.
  static const int insuranceExpiryReminderDays = 30;

  /// Days before warranty expiry at which reminders start.
  static const int warrantyExpiryReminderDays = 60;

  /// Days before the EMI due date at which "due soon" reminders are created.
  static const int emiDueSoonReminderDays = 3;

  /// Grace period (days) after an EMI due date before it is reported as overdue.
  static const int emiGraceDays = 0;

  /// Default GST rate (percent) used when a product does not define one.
  static const double defaultTaxRate = 18.0;

  /// Currency code used across the business (Indian market default).
  static const String currencyCode = 'INR';

  /// Symbol used for amounts in the UI.
  static const String currencySymbol = '\u20B9';

  /// Supabase realtime channel used for notifications.
  static const String realtimeChannel = 'public';

  /// Prefix used for generated document numbers while offline.
  static const String offlineDocPrefix = 'OFF';

  /// Maximum bytes for a single image upload before client-side compression
  /// is mandatory.
  static const int maxImageUploadBytes = 8 * 1024 * 1024;

  /// Target long-edge (px) for product photo compression.
  static const int productImageMaxWidth = 1600;

  /// Quality (0..100) for compressed JPEG product photos.
  static const int productImageQuality = 82;

  /// Target long-edge (px) for product thumbnails.
  static const int thumbnailSize = 400;

  /// Quality (0..100) for thumbnail JPEGs.
  static const int thumbnailQuality = 85;
}
