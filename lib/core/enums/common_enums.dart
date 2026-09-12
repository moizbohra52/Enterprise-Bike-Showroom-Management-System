/// Shared enums used across features.

/// Operations queued for offline synchronization.
enum SyncOperation {
  create('create'),
  update('update'),
  delete('delete'),
  payment('payment'),
  sale('sale'),
  service('service');

  const SyncOperation(this.value);
  final String value;

  static SyncOperation fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncOperation.create,
    );
  }
}

/// Lifecycle of a queued synchronization operation.
enum SyncStatus {
  pending('pending'),
  syncing('syncing'),
  success('success'),
  failed('failed');

  const SyncStatus(this.value);
  final String value;

  static SyncStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncStatus.pending,
    );
  }
}

/// Reminder priority levels.
enum ReminderPriority {
  low('low'),
  normal('normal'),
  high('high'),
  urgent('urgent');

  const ReminderPriority(this.value);
  final String value;

  static ReminderPriority fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReminderPriority.normal,
    );
  }
}

/// Reminder lifecycle.
enum ReminderStatus {
  pending('pending'),
  sent('sent'),
  completed('completed'),
  cancelled('cancelled');

  const ReminderStatus(this.value);
  final String value;

  static ReminderStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReminderStatus.pending,
    );
  }
}

/// Actions captured in audit logs.
enum AuditAction {
  create('create'),
  update('update'),
  delete('delete'),
  cancel('cancel'),
  approve('approve'),
  reject('reject'),
  payment('payment'),
  login('login'),
  logout('logout'),
  stockTransfer('stock_transfer'),
  stockAdjustment('stock_adjustment'),
  reversal('reversal'),
  refund('refund');

  const AuditAction(this.value);
  final String value;

  static AuditAction fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => AuditAction.update,
    );
  }
}

/// Notification categories.
enum NotificationType {
  emi('emi'),
  service('service'),
  insurance('insurance'),
  warranty('warranty'),
  payment('payment'),
  approval('approval'),
  stock('stock'),
  system('system');

  const NotificationType(this.value);
  final String value;

  static NotificationType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => NotificationType.system,
    );
  }
}

/// Reminder categories.
enum ReminderType {
  emi('emi'),
  service('service'),
  insurance('insurance'),
  warranty('warranty'),
  payment('payment'),
  document('document'),
  custom('custom');

  const ReminderType(this.value);
  final String value;

  static ReminderType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReminderType.custom,
    );
  }
}
