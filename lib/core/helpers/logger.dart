import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:flutter/foundation.dart';

/// Log severity levels.
enum LogLevel { debug, info, warning, error, critical }

/// Centralized, environment-aware logger.
///
/// - Verbose `debug` logs are suppressed in production.
/// - Sensitive keys (passwords, tokens, secrets) are redacted before output.
class AppLogger {
  AppLogger._();

  /// Minimum level emitted; set by [init].
  static LogLevel minLevel = LogLevel.debug;

  static const List<String> _sensitiveKeys = <String>[
    'password',
    'new_password',
    'current_password',
    'token',
    'access_token',
    'refresh_token',
    'secret',
    'api_key',
    'authorization',
    'anon_key',
    'service_role',
  ];

  /// Configures logging for the active environment.
  static void init() {
    minLevel = EnvironmentConfig.debugLoggingEnabled
        ? LogLevel.debug
        : LogLevel.info;
  }

  static void debug(String tag, Object? message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.debug, tag, message, error: error, stackTrace: stackTrace);
  }

  static void info(String tag, Object? message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.info, tag, message, error: error, stackTrace: stackTrace);
  }

  static void warning(String tag, Object? message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.warning, tag, message, error: error, stackTrace: stackTrace);
  }

  static void error(String tag, Object? message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);
  }

  static void critical(String tag, Object? message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.critical, tag, message, error: error, stackTrace: stackTrace);
  }

  static void _log(
    LogLevel level,
    String tag,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) return;
    final String safeMessage = _sanitize(message).toString();
    final String prefix =
        '[${level.name.toUpperCase()}] $tag: $safeMessage';

    switch (level) {
      case LogLevel.debug:
        debugPrint(prefix);
        break;
      case LogLevel.info:
        debugPrint(prefix);
        break;
      case LogLevel.warning:
        debugPrint('$prefix${error != null ? ' | error: ${_sanitize(error)}' : ''}');
        break;
      case LogLevel.error:
      case LogLevel.critical:
        debugPrint('$prefix');
        if (error != null) {
          debugPrint('  error: ${_sanitize(error)}');
        }
        if (stackTrace != null && !kReleaseMode) {
          debugPrint('  trace: $stackTrace');
        }
        break;
    }
  }

  /// Redacts sensitive values in maps/objects before logging.
  static Object? _sanitize(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<dynamic, Object?> e in value.entries)
          e.key.toString():
              _isSensitiveKey(e.key.toString()) ? '****' : _sanitize(e.value),
      };
    }
    if (value is String && value.length > 400) {
      return '${value.substring(0, 400)}...(truncated)';
    }
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final String lower = key.toLowerCase();
    return _sensitiveKeys.any((String s) => lower.contains(s));
  }
}
