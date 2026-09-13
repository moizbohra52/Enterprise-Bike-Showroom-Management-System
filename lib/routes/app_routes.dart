/// Centralized route names. All navigation goes through these constants.
class AppRoutes {
  AppRoutes._();

  // Auth
  static const String splash = '/splash';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  // Shell
  static const String dashboard = '/dashboard';
  static const String forbidden = '/forbidden';

  // Showrooms
  static const String showrooms = '/showrooms';
  static const String showroomForm = '/showrooms/form';
  static const String showroomDetails = '/showrooms/details';

  // Users & roles
  static const String users = '/users';
  static const String userForm = '/users/form';
  static const String userDetails = '/users/details';

  static const String roles = '/roles';
  static const String rolePermissions = '/roles/permissions';

  // Products & inventory
  static const String products = '/products';
  static const String productForm = '/products/form';
  static const String productDetails = '/products/details';

  static const String inventory = '/inventory';
  static const String inventoryDetails = '/inventory/details';
  static const String stockIn = '/inventory/stock-in';
  static const String stockTransfer = '/inventory/transfer';
  static const String stockAdjust = '/inventory/adjust';

  // Customers & vehicles
  static const String customers = '/customers';
  static const String customerForm = '/customers/form';
  static const String customerDetails = '/customers/details';
  static const String vehicleDetails = '/vehicles/details';
  static const String vehicleForm = '/vehicles/form';

  // Sales
  static const String sales = '/sales';
  static const String saleForm = '/sales/form';
  static const String saleDetails = '/sales/details';

  // Billing
  static const String billing = '/billing';
  static const String invoiceForm = '/billing/form';
  static const String invoiceDetails = '/billing/details';

  // Payments
  static const String payments = '/payments';
  static const String paymentForm = '/payments/form';
  static const String paymentDetails = '/payments/details';

  // Finance & EMI
  static const String finance = '/finance';
  static const String financeCompanyForm = '/finance/companies/form';
  static const String loans = '/finance/loans';
  static const String loanForm = '/finance/loans/form';
  static const String loanDetails = '/finance/loans/details';

  static const String emi = '/emi';
  static const String emiSchedule = '/emi/schedule';
  static const String emiPayment = '/emi/payment';

  // Purchases & suppliers
  static const String purchases = '/purchases';
  static const String purchaseForm = '/purchases/form';
  static const String purchaseDetails = '/purchases/details';
  static const String suppliers = '/purchases/suppliers';
  static const String supplierForm = '/purchases/suppliers/form';

  // Expenses
  static const String expenses = '/expenses';
  static const String expenseForm = '/expenses/form';
  static const String expenseDetails = '/expenses/details';

  // Accounting
  static const String accounting = '/accounting';
  static const String accountForm = '/accounting/accounts/form';
  static const String accountingManualEntry = '/accounting/manual-entry';
  static const String accountingTransactions = '/accounting/transactions';
  static const String accountingTransactionDetails =
      '/accounting/transactions/details';

  // Service
  static const String service = '/service';
  static const String serviceForm = '/service/form';
  static const String serviceDetails = '/service/details';
  static const String freeService = '/free-service';
  static const String freeServicePlans = '/free-service/plans';

  // Warranty & insurance
  static const String warranty = '/warranty';
  static const String warrantyDetails = '/warranty/details';
  static const String insurance = '/insurance';
  static const String insuranceForm = '/insurance/form';
  static const String insuranceDetails = '/insurance/details';

  // Reminders & notifications
  static const String reminders = '/reminders';
  static const String remindersForm = '/reminders/form';
  static const String notifications = '/notifications';

  // Reports
  static const String reports = '/reports';
  static const String report = '/reports/view';

  // Documents & audit
  static const String documents = '/documents';
  static const String audit = '/audit';

  // Settings
  static const String settings = '/settings';

  /// Detail route with id: `/customers/details/:id`.
  static String withId(String route, String id) => '$route/$id';
}
