/// Physical bike stock status.
enum InventoryStatus {
  available('available'),
  reserved('reserved'),
  sold('sold'),
  demo('demo'),
  damaged('damaged'),
  inTransit('in_transit'),
  returned('returned');

  const InventoryStatus(this.value);
  final String value;

  static InventoryStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => InventoryStatus.available,
    );
  }
}

/// Stock transfer workflow status.
enum TransferStatus {
  pending('pending'),
  inTransit('in_transit'),
  completed('completed'),
  cancelled('cancelled');

  const TransferStatus(this.value);
  final String value;

  static TransferStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => TransferStatus.pending,
    );
  }
}
