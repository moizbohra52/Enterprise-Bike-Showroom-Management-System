/// Purchase order lifecycle.
enum PurchaseStatus {
  pending('pending'),
  ordered('ordered'),
  partial('partial'),
  received('received'),
  completed('completed'),
  cancelled('cancelled');

  const PurchaseStatus(this.value);
  final String value;

  static PurchaseStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => PurchaseStatus.pending,
    );
  }
}
