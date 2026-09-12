import 'package:enterprise_bike_showroom/core/enums/common_enums.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A single pending operation in the offline sync queue.
///
/// Persisted in Hive (`app_sync_queue` box) and processed by
/// [SyncService] when connectivity returns.
class SyncQueueEntry {
  SyncQueueEntry({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.revision,
    this.retryCount = 0,
    this.lastError,
    this.status = SyncStatus.pending,
    this.conflict = false,
  });

  /// Queue entry id (local uuid).
  final String? id;

  /// Entity type, e.g. `customer`, `sale`, `payment`.
  final String entityType;

  /// Local or server id of the affected entity.
  final String entityId;

  /// What to do once online.
  final SyncOperation operation;

  /// Full entity payload (create) or update patch (update).
  final Map<String, dynamic> payload;

  /// When the operation was queued.
  final DateTime createdAt;

  /// Server `updated_at` captured when the operation was created; used for
  /// conflict detection.
  final String? revision;

  /// How many sync attempts failed so far.
  final int retryCount;

  /// Last error message (null when healthy).
  final String? lastError;

  /// Queue status.
  final SyncStatus status;

  /// True when server and local versions diverged; resolution is required.
  final bool conflict;

  SyncQueueEntry copyWith({
    String? id,
    String? entityId,
    SyncOperation? operation,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    String? revision,
    int? retryCount,
    String? lastError,
    SyncStatus? status,
    bool? conflict,
  }) {
    return SyncQueueEntry(
      id: id ?? this.id,
      entityType: entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      revision: revision ?? this.revision,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError,
      status: status ?? this.status,
      conflict: conflict ?? this.conflict,
    );
  }

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    return SyncQueueEntry(
      id: SafeJson.asId(json['id']),
      entityType: SafeJson.asText(json['entity_type'], fallback: 'unknown'),
      entityId: SafeJson.asText(json['entity_id']),
      operation: SyncOperation.fromWire(SafeJson.asString(json['operation'])),
      payload: SafeJson.asMap(json['payload']),
      createdAt: SafeJson.asDate(json['created_at']) ?? DateTime.now(),
      revision: SafeJson.asString(json['revision']),
      retryCount: SafeJson.asIntOr(json['retry_count'], 0),
      lastError: SafeJson.asString(json['last_error']),
      status: SyncStatus.fromWire(SafeJson.asString(json['status'])),
      conflict: SafeJson.asBoolOr(json['conflict'], false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation.value,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        if (revision != null) 'revision': revision,
        'retry_count': retryCount,
        if (lastError != null) 'last_error': lastError,
        'status': status.value,
        'conflict': conflict,
      };
}

/// Result of applying a queued operation on the server.
class SyncOperationResult {
  SyncOperationResult({
    required this.success,
    this.conflict = false,
    this.message,
    this.serverId,
    this.serverUpdatedAt,
  });

  final bool success;
  final bool conflict;
  final String? message;
  final String? serverId;
  final DateTime? serverUpdatedAt;

  static SyncOperationResult ok({String? serverId, DateTime? serverUpdatedAt}) =>
      SyncOperationResult(
        success: true,
        serverId: serverId,
        serverUpdatedAt: serverUpdatedAt,
      );

  static SyncOperationResult conflictWith(String reason,
          {String? serverVersion}) =>
      SyncOperationResult(
        success: false,
        conflict: true,
        message: reason,
      );

  static SyncOperationResult fail(String reason) =>
      SyncOperationResult(success: false, message: reason);
}

/// Handler registered per entity type: applies one queued operation to the
/// remote backend.
typedef SyncOperationHandler =
    Future<SyncOperationResult> Function(SyncQueueEntry operation);
