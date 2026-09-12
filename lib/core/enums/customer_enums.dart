/// Customer segmentation.
enum CustomerType {
  retail('retail'),
  dealer('dealer'),
  corporate('corporate'),
  financier('financier');

  const CustomerType(this.value);
  final String value;

  static CustomerType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => CustomerType.retail,
    );
  }
}

/// Customer account status.
enum CustomerStatus {
  active('active'),
  inactive('inactive'),
  blocked('blocked');

  const CustomerStatus(this.value);
  final String value;

  static CustomerStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => CustomerStatus.active,
    );
  }
}

/// Status of a customer-owned vehicle.
enum VehicleStatus {
  active('active'),
  inactive('inactive'),
  transferred('transferred'),
  scrapped('scrapped');

  const VehicleStatus(this.value);
  final String value;

  static VehicleStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => VehicleStatus.active,
    );
  }
}
