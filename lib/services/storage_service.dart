import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart'
    show AppException, NetworkException, RequestTimeoutException;
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';

/// Supabase Storage wrapper.
///
/// - Private buckets by default; public URLs only for product images.
/// - Signed URLs for confidential documents.
/// - Upload progress + retry-friendly (idempotent upsert).
class StorageService {
  StorageService();

  /// The Supabase client.
  SupabaseClient get client => Supabase.instance.client;

  /// Uploads a file to `bucket/path` (upsert). Returns the storage path.
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required File file,
    void Function(int received, int total)? onProgress,
    bool upsert = true,
  }) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: upsert),
          );
      AppLogger.info('STORAGE', 'uploaded $bucket/$path');
      return path;
    } catch (e) {
      AppLogger.error('STORAGE', 'upload failed $bucket/$path', error: e);
      throw ErrorMapper.map(e);
    }
  }

  /// Uploads raw bytes (e.g. a generated PDF).
  Future<String> uploadBytes({
    required String bucket,
    required String path,
    required List<int> bytes,
  }) async {
    try {
      await client.storage.from(bucket).uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(upsert: true),
          );
      return path;
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Public URL (only valid for public-read buckets).
  String getPublicUrl({required String bucket, required String path}) {
    return client.storage.from(bucket).getPublicUrl(path);
  }

  /// Signed URL for private files (default 1 hour).
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    int expiresIn = 3600,
  }) async {
    try {
      final String url = await client.storage
          .from(bucket)
          .createSignedUrl(path, expiresIn);
      return url;
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Best-effort display URL: public for public buckets, signed otherwise.
  Future<String> displayUrl({
    required String bucket,
    required String path,
  }) async {
    if (path.isEmpty) return '';
    if (SupabaseConfig.isPublicBucket(bucket)) {
      return getPublicUrl(bucket: bucket, path: path);
    }
    try {
      return await createSignedUrl(bucket: bucket, path: path);
    } catch (e) {
      AppLogger.warning('STORAGE', 'signed url failed for $path', error: e);
      return '';
    }
  }

  /// Downloads bytes from storage.
  Future<Uint8List> downloadBytes({
    required String bucket,
    required String path,
  }) async {
    try {
      return await client.storage.from(bucket).download(path);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Deletes files (storage layer only; DB rows are handled by repositories).
  Future<void> deleteFiles({
    required String bucket,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) return;
    try {
      await client.storage.from(bucket).remove(paths);
      AppLogger.info('STORAGE', 'deleted ${paths.length} file(s) from $bucket');
    } catch (e) {
      AppLogger.warning('STORAGE', 'delete failed', error: e);
      throw ErrorMapper.map(e);
    }
  }

  /// Moves/renames a stored object.
  Future<void> moveFile({
    required String bucket,
    required String fromPath,
    required String toPath,
  }) async {
    try {
      await client.storage.from(bucket).move(fromPath, toPath);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Lists objects under a folder prefix.
  Future<List<FileObject>> listFiles({
    required String bucket,
    String folder = '',
  }) async {
    try {
      return await client.storage.from(bucket).list(
            path: folder,
            searchOptions: SearchOptions(limit: 200),
          );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Upload with one automatic retry on transient failure.
  Future<String> uploadWithRetry({
    required String bucket,
    required String path,
    required File file,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      return await uploadFile(
        bucket: bucket,
        path: path,
        file: file,
        onProgress: onProgress,
      );
    } on AppException catch (first) {
      if (first is! NetworkException &&
          first is! RequestTimeoutException &&
          first.code != 'network_error' &&
          first.code != 'timeout') {
        rethrow;
      }
      AppLogger.warning('STORAGE', 'retrying upload $path');
      return uploadFile(
        bucket: bucket,
        path: path,
        file: file,
        onProgress: onProgress,
      );
    }
  }
}

