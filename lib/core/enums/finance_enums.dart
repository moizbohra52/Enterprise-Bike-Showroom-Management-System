/// Loan lifecycle.
enum LoanStatus {
  active('active'),
  closed('closed'),
  defaulted('defaulted'),
  cancelled('cancelled');

  const LoanStatus(this.value);
  final String value;

  static LoanStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => LoanStatus.active,
    );
  }
}

/// Interest calculation method.
enum InterestType {
  /// Reducing (reducing balance) interest - standard EMI formula.
  reducing('reducing'),

  /// Flat interest calculated on the original principal.
  flat('flat');

  const InterestType(this.value);
  final String value;

  static InterestType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => InterestType.reducing,
    );
  }
}

/// EMI installment status.
enum EmiStatus {
  upcoming('upcoming'),
  due('due'),
  partial('partial'),
  paid('paid'),
  overdue('overdue'),
  cancelled('cancelled');

  const EmiStatus(this.value);
  final String value;

  static EmiStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => EmiStatus.upcoming,
    );
  }
}
