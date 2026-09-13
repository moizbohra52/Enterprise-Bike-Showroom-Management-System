import 'dart:async';

import 'package:dio/dio.dart';

import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';

/// Injects the current Supabase bearer token into outgoing requests.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.tokenProvider);

  /// Returns the current access token (null when signed out).
  final String? Function() tokenProvider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String? token = tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
      options.headers['apikey'] = options.headers['apikey'] ??
          token; // some edge functions expect apikey
    }
    super.onRequest(options, handler);
  }
}

/// Environment-aware request/response logging.
///
/// Never logs request bodies containing credentials; query params and
/// headers are sanitized.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({this.enabled = true});

  final bool enabled;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) {
      AppLogger.debug(
        'HTTP',
        '→ ${options.method} ${options.uri.path} '
            '${options.queryParameters.isEmpty ? '' : options.queryParameters}',
      );
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (enabled) {
      AppLogger.debug(
        'HTTP',
        '← ${response.statusCode} ${response.requestOptions.uri.path}',
      );
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled) {
      AppLogger.warning(
        'HTTP',
        '✗ ${err.requestOptions.method} ${err.requestOptions.uri.path} '
            '${err.type.name}',
        error: err.message,
      );
    }
    super.onError(err, handler);
  }
}

/// Maps Dio errors to [AppException] and retries idempotent requests on
/// transient network failures.
class ErrorInterceptor extends Interceptor {
  ErrorInterceptor({int maxRetries = AppConfig.maxRetryAttempts})
      : maxRetries = maxRetries;

  final int maxRetries;
  final Map<String, int> _attempts = <String, int>{};

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final bool retryable = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        (err.type == DioExceptionType.unknown &&
            err.requestOptions.method == 'GET');
    final String key = err.requestOptions.uri.toString();
    final int attempt = _attempts[key] ?? 0;

    if (retryable && attempt < maxRetries) {
      _attempts[key] = attempt + 1;
      AppLogger.info('HTTP',
          'Retrying ${err.requestOptions.uri.path} (attempt ${attempt + 1})');
      Future<void>.delayed(const Duration(milliseconds: 500 * (attempt + 1)))
          .then((_) {
        handler.resolve(Dio(
              options: BaseOptions(),
            ).fetch<dynamic>(err.requestOptions));
      }).catchError((Object e) {
        _attempts.remove(key);
        handler.reject(_toAppDioError(e, err));
      });
      return;
    }

    _attempts.remove(key);
    final AppException appError = ErrorMapper.map(err);
    if (appError is NetworkException || appError is RequestTimeoutException) {
      handler.reject(DioException(
        requestOptions: err.requestOptions,
        error: appError,
        type: err.type,
      ));
      return;
    }
    handler.reject(err);
  }

  DioException _toAppDioError(Object e, DioException original) {
    if (e is DioException) return e;
    return DioException(
      requestOptions: original.requestOptions,
      error: ErrorMapper.map(e),
      type: DioExceptionType.unknown,
    );
  }
}
