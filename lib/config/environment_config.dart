import 'app_config.dart';

/// Supported deployment environments.
enum AppEnvironment { development, staging, production }

/// Centralized environment configuration.
///
/// Values are injected at build time with `--dart-define` so that no secret
/// is ever committed to source control. Per-environment defaults below are
/// used only when the corresponding dart-define is not provided (development
/// convenience); production builds must always be built with real values.
class EnvironmentConfig {
  EnvironmentConfig._();

  /// Selected environment name (`ENV` dart-define, default `development`).
  /// Default is a string literal — enum `.name` is not a compile-time constant
  /// usable inside `String.fromEnvironment`.
  static const String _envName = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );

  /// Supabase project URL (`SUPABASE_URL` dart-define).
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase public anon key (`SUPABASE_ANON_KEY` dart-define).
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Resolved environment.
  static AppEnvironment get environment {
    return AppEnvironment.values.firstWhere(
      (e) => e.name == _envName,
      orElse: () => AppEnvironment.development,
    );
  }

  static bool get isDevelopment => environment == AppEnvironment.development;
  static bool get isStaging => environment == AppEnvironment.staging;
  static bool get isProduction => environment == AppEnvironment.production;

  /// Human readable environment label.
  static String get environmentLabel =>
      environment == AppEnvironment.development
          ? 'Development'
          : environment == AppEnvironment.staging
              ? 'Staging'
              : 'Production';

  /// Supabase URL for the current environment.
  static String get supabaseUrl {
    if (_supabaseUrl.isNotEmpty) return _supabaseUrl;
    switch (environment) {
      case AppEnvironment.production:
      case AppEnvironment.staging:
        throw StateError(
          'SUPABASE_URL must be provided via --dart-define for '
          '${environment.name} builds.',
        );
      case AppEnvironment.development:
        return 'https://development-placeholder.supabase.co';
    }
  }

  /// Supabase anon (public) key for the current environment.
  static String get supabaseAnonKey {
    if (_supabaseAnonKey.isNotEmpty) return _supabaseAnonKey;
    if (environment != AppEnvironment.development) {
      throw StateError(
        'SUPABASE_ANON_KEY must be provided via --dart-define for '
        '${environment.name} builds.',
      );
    }
    return 'development-placeholder-anon-key';
  }

  /// True when the configured Supabase values are still placeholders.
  static bool get isPlaceholderBackend {
    return supabaseUrl.contains('placeholder') ||
        supabaseAnonKey.contains('placeholder');
  }

  /// Whether verbose debug logging is allowed.
  static bool get debugLoggingEnabled => !isProduction;

  /// Default showroom code used for the very first onboarding showroom.
  static const String defaultShowroomCode = 'HSR-001';

  /// Application user agent suffix appended to audit logs.
  static String get userAgent => '${AppConfig.appName}/${AppConfig.appVersion} '
      '(${environment.name})';
}
