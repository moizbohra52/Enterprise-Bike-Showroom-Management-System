/// Expense approval lifecycle.
enum ExpenseStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  paid('paid');

  const ExpenseStatus(this.value);
  final String value;

  static ExpenseStatus fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => ExpenseStatus.pending,
    );
  }
}

/// Seed expense categories (mirrors migration 014_seed_data.sql).
class ExpenseCategoryNames {
  ExpenseCategoryNames._();

  static const List<String> defaults = <String>[
    'Rent',
    'Electricity',
    'Salary',
    'Transport',
    'Marketing',
    'Maintenance',
    'Office',
    'Fuel',
    'Other',
  ];
}
