/// Accepted payment methods.
enum PaymentMethod {
  cash('cash'),
  upi('upi'),
  card('card'),
  bankTransfer('bank_transfer'),
  cheque('cheque'),
  finance('finance'),
  online('online'),
  mixed('mixed');

  const PaymentMethod(this.value);
  final String value;

  static PaymentMethod fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

/// Payment lifecycle. Financial payments are never physically deleted; they
/// are cancelled or reversed instead.
enum PaymentStatus {
  pending('pending'),
  completed('completed'),
  partial('partial'),
  refunded('refunded'),
  cancelled('cancelled'),
  reversed('reversed');

  const PaymentStatus(this.value);
  final String value;

  static PaymentStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => PaymentStatus.completed,
    );
  }
}
