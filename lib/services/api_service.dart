import 'dart:io';

import 'package:dio/dio.dart';

import 'package:enterprise_bike_showroom/core/network/api_client.dart';

/// Centralized API facade over [ApiClient].
///
/// Repositories use this for any REST endpoint outside the Supabase SDK
/// (external payment gateways, SMS providers, health checks). Views never
/// touch Dio directly.
class ApiService {
  ApiService({ApiClient? client}) : client = client ?? ApiClient();

  /// The underlying client (already configured with interceptors).
  final ApiClient client;

  /// Wires the auth token provider and builds the Dio instance.
  Future<void> init({String? Function()? tokenProvider}) async {
    client.tokenProvider =
        tokenProvider ?? client.tokenProvider ?? (() => null);
    await client.init();
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      client.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      client.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      client.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      client.patch<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      client.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

  Future<Response<T>> upload<T>(
    String path, {
    required File file,
    String fileField = 'file',
    Map<String, dynamic>? queryParameters,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) =>
      client.upload<T>(
        path,
        file: file,
        fileField: fileField,
        queryParameters: queryParameters,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  Future<File> download(
    String url,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) =>
      client.download(url, savePath,
          onProgress: onProgress, cancelToken: cancelToken);

  CancelToken newCancelToken() => client.newCancelToken();
}
