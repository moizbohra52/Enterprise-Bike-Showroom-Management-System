/// Invoice types supported by the billing module.
enum InvoiceType {
  sale('sale'),
  service('service'),
  accessory('accessory'),
  other('other');

  const InvoiceType(this.value);
  final String value;

  static InvoiceType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => InvoiceType.sale,
    );
  }
}

/// Invoice lifecycle. Finalized invoices are immutable and may only be
/// cancelled/reversed through controlled operations.
enum InvoiceStatus {
  draft('draft'),
  finalized('finalized'),
  partiallyPaid('partially_paid'),
  paid('paid'),
  overdue('overdue'),
  cancelled('cancelled'),
  reversed('reversed');

  const InvoiceStatus(this.value);
  final String value;

  static InvoiceStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => InvoiceStatus.draft,
    );
  }
}
