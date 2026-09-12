import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/constants/storage_keys.dart';
import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';

/// Hive-based local persistence:
/// - read-through cache (lists & entities)
/// - offline drafts (sales, services, payments)
/// - synchronization queue
///
/// The implementation is intentionally thin: feature code talks to
/// repositories, and repositories decide what to cache/queue. Swapping Hive
/// for SQLite later only requires re-implementing this class.
class LocalDatabaseService {
  LocalDatabaseService();

  Box<dynamic>? _cacheBox;
  Box<dynamic>? _draftsBox;
  Box<dynamic>? _queueBox;

  Box<dynamic> get cacheBox => _requireBox(_cacheBox, HiveBoxNames.cache);
  Box<dynamic> get draftsBox => _requireBox(_draftsBox, HiveBoxNames.drafts);
  Box<dynamic> get queueBox => _requireBox(_queueBox, HiveBoxNames.syncQueue);

  bool get isInitialized =>
      _cacheBox != null && _draftsBox != null && _queueBox != null;

  /// Opens the boxes (idempotent).
  Future<void> init() async {
    if (isInitialized) return;
    if (!Hive.isBoxOpen(HiveBoxNames.cache)) {
      _cacheBox = await Hive.openBox<dynamic>(HiveBoxNames.cache);
    }
    if (!Hive.isBoxOpen(HiveBoxNames.drafts)) {
      _draftsBox = await Hive.openBox<dynamic>(HiveBoxNames.drafts);
    }
    if (!Hive.isBoxOpen(HiveBoxNames.syncQueue)) {
      _queueBox = await Hive.openBox<dynamic>(HiveBoxNames.syncQueue);
    }
    AppLogger.info('LOCALDB', 'opened boxes');
  }

  Box<dynamic> _requireBox(Box<dynamic>? box, String name) {
    if (box == null) {
      throw StateError('LocalDatabaseService not initialized (box: $name)');
    }
    return box;
  }

  // ---------------------------------------------------------------- cache

  /// Stores a JSON-serializable cache entry with an optional TTL.
  Future<void> putCache(String key, Map<String, dynamic> data,
      {Duration? ttl}) async {
    await cacheBox.put(
      key,
      jsonEncode(<String, dynamic>{
        'expires_at':
            ttl == null ? null : DateTime.now().add(ttl).millisecondsSinceEpoch,
        'data': data,
      }),
    );
  }

  /// Reads a cache entry; returns null when missing or expired.
  Future<Map<String, dynamic>?> getCache(String key) async {
    final dynamic raw = cacheBox.get(key);
    if (raw is! String) return null;
    try {
      final Map<String, dynamic> envelope =
          jsonDecode(raw) as Map<String, dynamic>;
      final dynamic expires = envelope['expires_at'];
      if (expires is int && expires < DateTime.now().millisecondsSinceEpoch) {
        await cacheBox.delete(key);
        return null;
      }
      final dynamic data = envelope['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is Map) {
        return <String, dynamic>{
          for (final MapEntry<dynamic, dynamic> e in data.entries)
            e.key.toString(): e.value,
        };
      }
      return null;
    } catch (e) {
      AppLogger.warning('LOCALDB', 'corrupt cache entry: $key', error: e);
      return null;
    }
  }

  Future<void> removeCache(String key) => cacheBox.delete(key);

  Future<void> clearCache() async {
    await cacheBox.clear();
    AppLogger.info('LOCALDB', 'cache cleared');
  }

  // --------------------------------------------------------------- drafts

  static String _draftKey(String entityType, String entityId) =>
      'draft:$entityType:$entityId';

  /// Saves/updates an offline draft payload.
  Future<void> saveDraft(
    String entityType,
    String entityId,
    Map<String, dynamic> payload,
  ) async {
    await draftsBox.put(
      _draftKey(entityType, entityId),
      jsonEncode(<String, dynamic>{
        'entity_type': entityType,
        'entity_id': entityId,
        'saved_at': DateTime.now().toIso8601String(),
        'payload': payload,
      }),
    );
  }

  /// Reads a draft payload (null when absent).
  Future<Map<String, dynamic>?> getDraft(String entityType, String entityId) async {
    final dynamic raw = draftsBox.get(_draftKey(entityType, entityId));
    if (raw is! String) return null;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map) {
        final Map<String, dynamic> envelope = <String, dynamic>{
          for (final MapEntry<dynamic, dynamic> e in decoded.entries)
            e.key.toString(): e.value,
        };
        final dynamic payload = envelope['payload'];
        return payload is Map
            ? <String, dynamic>{
                for (final MapEntry<dynamic, dynamic> e in payload.entries)
                  e.key.toString(): e.value,
              }
            : <String, dynamic>{};
      }
    } catch (e) {
      AppLogger.warning('LOCALDB', 'corrupt draft', error: e);
    }
    return null;
  }

  Future<void> deleteDraft(String entityType, String entityId) =>
      draftsBox.delete(_draftKey(entityType, entityId));

  /// Ids of all drafts for an entity type.
  List<String> draftIds(String entityType) {
    final String prefix = 'draft:$entityType:';
    return queueKeys().where((String k) => k.startsWith(prefix)).toList();
  }

  Set<String> queueKeys() => <String>{
        for (final dynamic key in draftsBox.keys) key.toString(),
      };

  // ------------------------------------------------------------- sync queue

  /// Adds an operation to the queue (or refreshes an existing one).
  Future<void> enqueue(SyncQueueEntry operation) async {
    await queueBox.put(operation.id, jsonEncode(operation.toJson()));
  }

  /// All operations awaiting sync (PENDING, plus FAILED with retries left).
  Future<List<SyncQueueEntry>> pendingOperations(
      {String? entityType}) async {
    final List<SyncQueueEntry> ops = <SyncQueueEntry>[];
    for (final dynamic key in queueBox.keys) {
      final dynamic raw = queueBox.get(key);
      if (raw is! String) continue;
      try {
        final SyncQueueEntry op =
            SyncQueueEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final bool actionable =
            op.status == SyncStatus.pending ||
            (op.status == SyncStatus.failed &&
                op.retryCount < AppConfig.maxRetryAttempts);
        if (actionable &&
            (entityType == null || op.entityType == entityType)) {
          ops.add(op);
        }
      } catch (e) {
        AppLogger.warning('LOCALDB', 'corrupt queue entry: $key', error: e);
      }
    }
    ops.sort((SyncQueueEntry a, SyncQueueEntry b) =>
        a.createdAt.isBefore(b.createdAt) ? -1 : 1);
    return ops;
  }

  /// Conflicts awaiting manual resolution.
  Future<List<SyncQueueEntry>> conflictedOperations(
      {String? entityType}) async {
    final List<SyncQueueEntry> ops = <SyncQueueEntry>[];
    for (final dynamic key in queueBox.keys) {
      final dynamic raw = queueBox.get(key);
      if (raw is! String) continue;
      try {
        final SyncQueueEntry op =
            SyncQueueEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (op.conflict &&
            (entityType == null || op.entityType == entityType)) {
          ops.add(op);
        }
      } catch (_) {
        // skip corrupt
      }
    }
    return ops;
  }

  Future<void> markSyncing(SyncQueueEntry operation) async {
    operation.status = SyncStatus.syncing;
    await queueBox.put(operation.id, jsonEncode(operation.toJson()));
  }

  Future<void> completeOperation(
    SyncQueueEntry operation, {
    required String? serverId,
    required DateTime? serverUpdatedAt,
  }) async {
    operation.status = SyncStatus.success;
    operation.conflict = false;
    operation.lastError = null;
    if (serverId != null) operation.entityId = serverId;
    if (serverUpdatedAt != null) {
      operation.revision = serverUpdatedAt.toIso8601String();
    }
    await queueBox.put(operation.id, jsonEncode(operation.toJson()));
  }

  Future<void> failOperation(SyncQueueEntry operation, String error) async {
    operation.status =
        operation.retryCount >= AppConfig.maxRetryAttempts
            ? SyncStatus.failed
            : SyncStatus.pending;
    operation.retryCount += 1;
    operation.lastError = error;
    operation.conflict = false;
    await queueBox.put(operation.id, jsonEncode(operation.toJson()));
  }

  Future<void> markConflict(
    SyncQueueEntry operation,
    String reason, {
    String? serverVersion,
  }) async {
    operation.conflict = true;
    operation.lastError = 'CONFLICT: $reason';
    if (serverVersion != null) operation.revision = serverVersion;
    await queueBox.put(operation.id, jsonEncode(operation.toJson()));
  }

  Future<void> removeOperation(String id) => queueBox.delete(id);

  /// Purges old SUCCESS entries older than [maxAge].
  Future<void> purgeSuccess({Duration maxAge = const Duration(days: 7)}) async {
    final DateTime cutoff = DateTime.now().subtract(maxAge);
    final List<dynamic> keys = <dynamic>[];
    for (final dynamic key in queueBox.keys) {
      final dynamic raw = queueBox.get(key);
      if (raw is! String) continue;
      try {
        final SyncQueueEntry op =
            SyncQueueEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (op.status == SyncStatus.success &&
            op.createdAt.isBefore(cutoff)) {
          keys.add(key);
        }
      } catch (_) {
        keys.add(key); // corrupt -> purge
      }
    }
    if (keys.isNotEmpty) {
      await queueBox.deleteAll(keys);
    }
  }

  Future<int> pendingCount() async {
    final List<SyncQueueEntry> ops = await pendingOperations();
    return ops.length;
  }

  /// Closes all boxes.
  Future<void> close() async {
    await _cacheBox?.close();
    await _draftsBox?.close();
    await _queueBox?.close();
    _cacheBox = null;
    _draftsBox = null;
    _queueBox = null;
  }
}
