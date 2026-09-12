/// Service (job card) type.
enum ServiceType {
  free('free'),
  paid('paid'),
  warranty('warranty');

  const ServiceType(this.value);
  final String value;

  static ServiceType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => ServiceType.paid,
    );
  }
}

/// Service workflow status.
enum ServiceStatus {
  booked('booked'),
  received('received'),
  inProgress('in_progress'),
  waitingForParts('waiting_for_parts'),
  completed('completed'),
  delivered('delivered'),
  cancelled('cancelled');

  const ServiceStatus(this.value);
  final String value;

  static ServiceStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => ServiceStatus.booked,
    );
  }
}

/// Job-card line item categories.
enum ServiceItemType {
  part('part'),
  labour('labour'),
  oil('oil'),
  consumable('consumable'),
  accessory('accessory'),
  other('other');

  const ServiceItemType(this.value);
  final String value;

  static ServiceItemType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => ServiceItemType.part,
    );
  }
}

/// Free-service schedule entry status.
enum FreeServiceStatus {
  upcoming('upcoming'),
  used('used'),
  expired('expired'),
  cancelled('cancelled');

  const FreeServiceStatus(this.value);
  final String value;

  static FreeServiceStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => FreeServiceStatus.upcoming,
    );
  }
}
