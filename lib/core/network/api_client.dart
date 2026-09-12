import 'dart:io';

import 'package:dio/dio.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/network/interceptors.dart';

/// Centralized HTTP client built on Dio.
///
/// Rules:
/// - Views and controllers NEVER call Dio directly; they go through
///   repositories, and repositories use [ApiClient] for any non-Supabase
///   REST endpoint (health checks, external gateways, webhooks).
/// - Supabase PostgREST/Auth/Storage traffic goes through the Supabase SDK
///   (`SupabaseService`), which carries the same auth token.
///
/// Features:
/// - Auth bearer header via [AuthInterceptor]
/// - Logging (environment aware)
/// - Centralized error mapping to [AppException]
/// - Automatic retry for idempotent network errors
/// - Timeouts, request cancellation, multipart upload, file download
class ApiClient {
  ApiClient({this.baseUrl = ''});

  /// Optional base URL prefix for the underlying Dio instance.
  String baseUrl;

  late final Dio dio;

  /// Current bearer token provider (wired to AuthService at startup).
  String? Function()? tokenProvider;

  /// Builds the Dio instance with the standard interceptor pipeline.
  Future<void> init() async {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        sendTimeout: AppConfig.apiTimeout,
        headers: <String, dynamic>{
          'Content-Type': 'application/json',
          'User-Agent': EnvironmentConfig.userAgent,
        },
      ),
    );
    dio.interceptors
      ..add(AuthInterceptor(tokenProvider ?? (() => null)))
      ..add(LoggingInterceptor(
          enabled: EnvironmentConfig.debugLoggingEnabled))
      ..add(ErrorInterceptor());
  }

  /// The raw Dio instance (interceptors already attached).
  Dio get client => dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _guarded<T>(() => dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        ));
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _guarded<T>(() => dio.post<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        ));
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _guarded<T>(() => dio.put<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        ));
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _guarded<T>(() => dio.patch<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        ));
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _guarded<T>(() => dio.delete<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        ));
  }

  /// Multipart upload with progress reporting.
  Future<Response<T>> upload<T>(
    String path, {
    required File file,
    String fileField = 'file',
    Map<String, dynamic>? queryParameters,
    Map<String, String> extraFields = const <String, String>{},
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final FormData formData = FormData();
    formData.file(fileField, file);
    extraFields.forEach((String k, String v) => formData.fields.add(k, v));
    try {
      return await dio.post<T>(
        path,
        data: formData,
        queryParameters: queryParameters,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );
    } on DioException catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Downloads a file to disk, returning the local file.
  Future<File> download(
    String url,
    String savePath, {
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      await dio.download(url, savePath, onReceiveProgress: onProgress,
          cancelToken: cancelToken);
      return File(savePath);
    } on DioException catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Creates a cancel token for long-running operations.
  CancelToken newCancelToken() => CancelToken();

  Future<Response<T>> _guarded<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      // ErrorInterceptor may have already wrapped the error.
      final AppException? wrapped =
          e.error is AppException ? e.error as AppException : null;
      if (wrapped != null) throw wrapped;
      throw ErrorMapper.map(e);
    }
  }
}
