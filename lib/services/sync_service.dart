import 'dart:async';

import 'package:enterprise_bike_showroom/common/models/sync_queue_entry.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/services/connectivity_service.dart';
import 'package:enterprise_bike_showroom/services/local_database_service.dart';

/// Drives offline -> online synchronization.
///
/// Flow:
/// ```
/// Connectivity detected
///   -> pending queue (Hive)
///   -> per-operation handler (repository)
///   -> server validation (RPC/RLS)
///   -> conflict resolution (deterministic; financial records are never
///      auto-overwritten - they are marked for manual resolution)
///   -> local cache update
/// ```
class SyncService {
  SyncService({
    required LocalDatabaseService local,
    required ConnectivityService connectivity,
  })  : _local = local,
        _connectivity = connectivity;

  final LocalDatabaseService _local;
  final ConnectivityService _connectivity;

  /// Reactive counters (mirrored into GetX controllers for the UI).
  int pendingCount = 0;
  int conflictCount = 0;
  bool isSyncing = false;
  String? lastError;
  DateTime? lastSyncAt;

  /// Cancels for external listeners, cleared on dispose.
  final List<CancelableListener> _cancels = <CancelableListener>[];

  /// Per-entity-type application handlers.
  final Map<String, SyncOperationHandler> handlers =
      <String, SyncOperationHandler>{};

  /// Listeners notified after every queue change (badge counts, banners).
  final List<void Function(SyncService service)> queueListeners =
      <void Function(SyncService service)>[];

  /// Entity types whose conflicts must never be auto-resolved.
  static const List<String> protectedEntities = <String>[
    'payment',
    'sale',
    'invoice',
    'emi',
    'loan',
  ];

  /// Registers the handler used to apply queued operations of [entityType].
  void registerHandler(String entityType, SyncOperationHandler handler) {
    handlers[entityType] = handler;
  }

  /// Starts listening for connectivity changes.
  void start() {
    _cancels.add(_connectivity.addListener((bool online) {
      if (online) {
        unawaited(syncNow());
      }
    }));
    unawaited(_refreshCounts());
  }

  /// Queues an operation for later sync.
  Future<void> enqueue(SyncQueueEntry operation) async {
    await _local.enqueue(operation);
    AppLogger.info('SYNC',
        'queued ${operation.operation.value} ${operation.entityType} '
        '${operation.entityId}');
    await _refreshCounts();
  }

  /// Processes the queue sequentially (safe against re-entrancy).
  Future<void> syncNow() async {
    if (isSyncing) return;
    if (!_connectivity.isOnline) return;
    isSyncing = true;
    try {
      final List<SyncQueueEntry> ops = await _local.pendingOperations();
      for (final SyncQueueEntry op in ops) {
        await _processOperation(op);
      }
      lastSyncAt = DateTime.now();
      await _local.purgeSuccess();
    } catch (e) {
      lastError = ErrorMapper.friendly(e);
      AppLogger.error('SYNC', 'sync run failed', error: e);
    } finally {
      isSyncing = false;
      await _refreshCounts();
    }
  }

  Future<void> _processOperation(SyncQueueEntry operation) async {
    final SyncOperationHandler? handler = handlers[operation.entityType];
    if (handler == null) {
      AppLogger.warning('SYNC', 'no handler for ${operation.entityType}');
      await _local.markConflict(operation, 'No sync handler registered.');
      return;
    }
    await _local.markSyncing(operation);
    try {
      final SyncOperationResult result = await handler(operation);
      if (result.conflict &&
          protectedEntities.contains(operation.entityType)) {
        // Financial integrity: never auto-overwrite; surface for resolution.
        await _local.markConflict(
          operation,
          result.message ?? 'Server data changed. Manual review required.',
        );
        AppLogger.warning('SYNC',
            'conflict on protected entity ${operation.entityType}: '
            '${operation.entityId}');
        return;
      }
      if (!result.success) {
        await _local.failOperation(operation, result.message ?? 'failed');
        lastError = result.message;
        return;
      }
      await _local.completeOperation(
        operation,
        serverId: result.serverId,
        serverUpdatedAt: result.serverUpdatedAt,
      );
      AppLogger.info('SYNC', 'synced ${operation.entityType} ${operation.entityId}');
    } catch (e) {
      final AppException mapped = ErrorMapper.map(e);
      if (mapped is ConflictException || mapped is ValidationException) {
        await _local.markConflict(operation, mapped.message);
        lastError = mapped.message;
        return;
      }
      await _local.failOperation(operation, mapped.message);
      lastError = mapped.message;
    }
  }

  Future<void> _refreshCounts({bool quiet = false}) async {
    try {
      pendingCount = await _local.pendingCount();
      final List<SyncQueueEntry> conflicts =
          await _local.conflictedOperations();
      conflictCount = conflicts.length;
    } catch (e) {
      AppLogger.warning('SYNC', 'count refresh failed', error: e);
    }
    for (final void Function(SyncService) listener
        in List<void Function(SyncService)>.of(queueListeners)) {
      try {
        listener(this);
      } catch (e) {
        AppLogger.error('SYNC', 'listener error', error: e);
      }
    }
  }

  /// Registers a queue-change listener; returns a cancel function.
  CancelableListener addListener(void Function(SyncService service) listener) {
    queueListeners.add(listener);
    return () => queueListeners.remove(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(void Function(SyncService service) listener) {
    queueListeners.remove(listener);
  }

  void dispose() {
    for (final CancelableListener cancel in _cancels) {
      cancel();
    }
    _cancels.clear();
    queueListeners.clear();
    handlers.clear();
  }
}
