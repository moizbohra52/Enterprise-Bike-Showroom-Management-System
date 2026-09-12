import 'dart:io';
import 'dart:typed_data';

import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/supabase_config.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/id_generator.dart';
import 'package:image/image.dart' as img;

/// Centralized image handling:
/// - compression & resize before upload
/// - thumbnails
/// - Supabase Storage upload with progress
/// - path management (`products/{productId}/...`)
class ImageService {
  ImageService({required StorageServiceRef storage}) : storage = storage;

  /// Storage backend.
  final StorageServiceRef storage;

  /// Compresses [source] to JPEG (max long edge [maxWidth]).
  /// Returns a new temp file; caller does not need to clean it up on web.
  Future<File> compressImage(
    File source, {
    int maxWidth = AppConfig.productImageMaxWidth,
    int quality = AppConfig.productImageQuality,
  }) async {
    try {
      final Uint8List bytes = await source.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw AppException('Could not read the image file.');
      }
      final int longest = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      img.Image resized = decoded;
      if (longest > maxWidth) {
        final double scale = maxWidth / longest;
        resized = img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
        );
      }
      final Uint8List encoded =
          img.encodeJpg(resized, quality: quality.clamp(1, 100));
      final File out = File(
        '${Directory.systemTemp.path}/img_${IdGenerator.uuid()}.jpg',
      );
      await out.writeAsBytes(encoded);
      return out;
    } catch (e) {
      AppLogger.error('IMAGE', 'compression failed', error: e);
      if (e is AppException) rethrow;
      throw AppException('Could not process the image.', details: e);
    }
  }

  /// Generates a square-ish thumbnail.
  Future<File> makeThumbnail(
    File source, {
    int size = AppConfig.thumbnailSize,
  }) async {
    try {
      final Uint8List bytes = await source.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw AppException('Could not read the image file.');
      }
      final int side = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      final int crop =
          (side / 2 - size / 2).clamp(0, side ~/ 2).round();
      final int cropEnd = (side / 2 + size / 2).clamp(0, side).round();
      final img.Image cropped = img.copyCrop(
        decoded,
        x: crop,
        y: crop,
        width: cropEnd - crop,
        height: cropEnd - crop,
      );
      final img.Image resized = img.copyResize(
        cropped,
        width: size,
        height: size,
      );
      final Uint8List encoded = img.encodeJpg(
        resized,
        quality: AppConfig.thumbnailQuality,
      );
      final File out = File(
        '${Directory.systemTemp.path}/thumb_${IdGenerator.uuid()}.jpg',
      );
      await out.writeAsBytes(encoded);
      return out;
    } catch (e) {
      AppLogger.error('IMAGE', 'thumbnail failed', error: e);
      if (e is AppException) rethrow;
      throw AppException('Could not create a thumbnail.', details: e);
    }
  }

  /// Uploads a product image (compressed) and returns the storage path.
  Future<String> uploadProductImage({
    required String productId,
    required File file,
    int index = 0,
    void Function(int received, int total)? onProgress,
  }) async {
    final File compressed = await compressImage(file);
    final String path = SupabaseConfig.storagePath(
      collection: 'products',
      entityId: productId,
      fileName: '${index}_${IdGenerator.uuid()}.jpg',
    );
    return storage.uploadWithRetry(
      bucket: StorageBuckets.productImages,
      path: path,
      file: compressed,
      onProgress: onProgress,
    );
  }

  /// Uploads a confidential document to a private bucket.
  Future<String> uploadDocument({
    required String bucket,
    required String collection,
    required String entityId,
    required File file,
    String? fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    final String name =
        fileName ?? '${collection}_${IdGenerator.uuid()}.bin';
    final String path =
        SupabaseConfig.storagePath(collection: collection, entityId: entityId, fileName: name);
    return storage.uploadWithRetry(
      bucket: bucket,
      path: path,
      file: file,
      onProgress: onProgress,
    );
  }

  /// Signed display URL for a private document.
  Future<String> documentUrl({
    required String bucket,
    required String path,
  }) async {
    return storage.displayUrl(bucket: bucket, path: path);
  }

  /// Deletes an image from storage.
  Future<void> deleteImage({
    required String bucket,
    required String path,
  }) async {
    await storage.deleteFiles(bucket: bucket, paths: <String>[path]);
  }
}

/// Typedef for the storage dependency (keeps DI registrations explicit).
typedef StorageServiceRef = StorageService;
