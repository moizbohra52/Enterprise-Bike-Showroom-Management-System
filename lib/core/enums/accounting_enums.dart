/// Double-entry account types.
enum AccountType {
  asset('ASSET'),
  liability('LIABILITY'),
  equity('EQUITY'),
  income('INCOME'),
  expense('EXPENSE');

  const AccountType(this.value);
  final String value;

  static AccountType fromWire(String? value) {
    return values.firstWhere(
      (e) => e.value == (value ?? '').toUpperCase(),
      orElse: () => AccountType.asset,
    );
  }
}

/// Seed chart-of-accounts template (mirrors migration 013_accounting.sql).
class AccountTemplates {
  AccountTemplates._();

  /// Default accounts created for every showroom:
  /// (code, name, type, parentCode).
  static const List<AccountTemplate> defaults = <AccountTemplate>[
    AccountTemplate('1000', 'Cash', 'ASSET', null),
    AccountTemplate('1100', 'Bank', 'ASSET', null),
    AccountTemplate('1200', 'Customer Receivable', 'ASSET', null),
    AccountTemplate('1300', 'Inventory', 'ASSET', null),
    AccountTemplate('2000', 'Supplier Payable', 'LIABILITY', null),
    AccountTemplate('2100', 'Tax Payable', 'LIABILITY', null),
    AccountTemplate('3000', 'Owner Equity', 'EQUITY', null),
    AccountTemplate('4000', 'Sales Revenue', 'INCOME', null),
    AccountTemplate('4100', 'Service Revenue', 'INCOME', null),
    AccountTemplate('4200', 'Other Income', 'INCOME', null),
    AccountTemplate('5000', 'Purchase', 'EXPENSE', null),
    AccountTemplate('5100', 'Discount Given', 'EXPENSE', null),
    AccountTemplate('5200', 'Salary Expense', 'EXPENSE', null),
    AccountTemplate('5300', 'Rent Expense', 'EXPENSE', null),
    AccountTemplate('5400', 'Marketing Expense', 'EXPENSE', null),
    AccountTemplate('5500', 'Other Expense', 'EXPENSE', null),
  ];
}

class AccountTemplate {
  const AccountTemplate(this.code, this.name, this.type, this.parentCode);

  final String code;
  final String name;
  final String type;
  final String? parentCode;
}
