/// Sales lifecycle status.
enum SaleStatus {
  draft('draft'),
  active('active'),
  completed('completed'),
  cancelled('cancelled'),
  reversed('reversed');

  const SaleStatus(this.value);
  final String value;

  static SaleStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => SaleStatus.active,
    );
  }
}

/// How a sale is financed.
enum SaleType {
  cash('cash'),
  credit('credit'),
  finance('finance'),
  exchange('exchange');

  const SaleType(this.value);
  final String value;

  static SaleType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => SaleType.cash,
    );
  }
}
