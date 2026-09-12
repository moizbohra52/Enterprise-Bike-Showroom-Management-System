/// Entity type identifiers used by the sync queue, audit logs and
/// attachments. These values must match the `entity_type` text values stored
/// in PostgreSQL (see DATABASE.md).
class EntityType {
  EntityType._();

  static const String showroom = 'showroom';
  static const String user = 'user';
  static const String product = 'product';
  static const String inventory = 'inventory';
  static const String customer = 'customer';
  static const String customerVehicle = 'customer_vehicle';
  static const String sale = 'sale';
  static const String invoice = 'invoice';
  static const String payment = 'payment';
  static const String loan = 'loan';
  static const String emi = 'emi';
  static const String financeCompany = 'finance_company';
  static const String supplier = 'supplier';
  static const String purchase = 'purchase';
  static const String expense = 'expense';
  static const String expenseCategory = 'expense_category';
  static const String serviceRecord = 'service_record';
  static const String freeServicePlan = 'free_service_plan';
  static const String warranty = 'warranty';
  static const String warrantyClaim = 'warranty_claim';
  static const String insurance = 'insurance_policy';
  static const String reminder = 'reminder';
  static const String notification = 'notification';
  static const String account = 'account';
  static const String attachment = 'attachment';
  static const String brand = 'brand';

  static const List<String> all = <String>[
    showroom,
    user,
    product,
    inventory,
    customer,
    customerVehicle,
    sale,
    invoice,
    payment,
    loan,
    emi,
    financeCompany,
    supplier,
    purchase,
    expense,
    expenseCategory,
    serviceRecord,
    freeServicePlan,
    warranty,
    warrantyClaim,
    insurance,
    reminder,
    notification,
    account,
    attachment,
    brand,
  ];
}

/// Reference types used by reminders, notifications and audit logs.
class ReferenceType {
  ReferenceType._();

  static const String sale = 'sale';
  static const String invoice = 'invoice';
  static const String payment = 'payment';
  static const String loan = 'loan';
  static const String emi = 'emi';
  static const String service = 'service';
  static const String vehicle = 'vehicle';
  static const String customer = 'customer';
  static const String warranty = 'warranty';
  static const String insurance = 'insurance';
  static const String purchase = 'purchase';
  static const String expense = 'expense';
  static const String document = 'document';
  static const String account = 'account';
  static const String stockTransfer = 'stock_transfer';
  static const String stockAdjustment = 'stock_adjustment';
}
