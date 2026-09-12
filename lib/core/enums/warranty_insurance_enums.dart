/// Warranty lifecycle.
enum WarrantyStatus {
  active('active'),
  expired('expired'),
  cancelled('cancelled'),
  voided('voided');

  const WarrantyStatus(this.value);
  final String value;

  static WarrantyStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => WarrantyStatus.active,
    );
  }
}

/// Warranty claim lifecycle.
enum WarrantyClaimStatus {
  open('open'),
  inReview('in_review'),
  approved('approved'),
  rejected('rejected'),
  resolved('resolved'),
  cancelled('cancelled');

  const WarrantyClaimStatus(this.value);
  final String value;

  static WarrantyClaimStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => WarrantyClaimStatus.open,
    );
  }
}

/// Insurance policy status.
enum InsuranceStatus {
  active('active'),
  expiringSoon('expiring_soon'),
  expired('expired'),
  cancelled('cancelled');

  const InsuranceStatus(this.value);
  final String value;

  static InsuranceStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => InsuranceStatus.active,
    );
  }
}
