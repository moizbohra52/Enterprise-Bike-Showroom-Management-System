/// Canonical permission strings used by GetX, navigation, Supabase RLS and
/// database functions.
///
/// Format: `module.action`.
class PermissionModules {
  PermissionModules._();

  static const String dashboard = 'dashboard';
  static const String showroom = 'showroom';
  static const String users = 'users';
  static const String roles = 'roles';
  static const String products = 'products';
  static const String inventory = 'inventory';
  static const String customers = 'customers';
  static const String sales = 'sales';
  static const String billing = 'billing';
  static const String payments = 'payments';
  static const String finance = 'finance';
  static const String emi = 'emi';
  static const String purchases = 'purchases';
  static const String expenses = 'expenses';
  static const String accounting = 'accounting';
  static const String service = 'service';
  static const String warranty = 'warranty';
  static const String insurance = 'insurance';
  static const String reminders = 'reminders';
  static const String notifications = 'notifications';
  static const String reports = 'reports';
  static const String documents = 'documents';
  static const String audit = 'audit';
  static const String settings = 'settings';
}

class PermissionActions {
  PermissionActions._();

  static const String view = 'view';
  static const String create = 'create';
  static const String edit = 'edit';
  static const String delete = 'delete';
  static const String export = 'export';
  static const String print = 'print';
  static const String approve = 'approve';
  static const String cancel = 'cancel';
  static const String complete = 'complete';
  static const String manage = 'manage';
  static const String transfer = 'transfer';
  static const String adjust = 'adjust';
  static const String reserve = 'reserve';
  static const String release = 'release';
  static const String bill = 'bill';
  static const String payment = 'payment';
  static const String discount = 'discount';
}

/// Builds and validates permission strings.
class Permissions {
  Permissions._();

  /// Builds `module.action`.
  static String of(String module, String action) => '$module.$action';

  /// Wildcard for an entire module (`module.*`).
  static String moduleWildcard(String module) => '$module.*';

  /// Wildcard for every module and action.
  static const String all = '*.*';

  /// Dashboard
  static const String dashboardView = 'dashboard.view';

  /// Showroom
  static const String showroomView = 'showroom.view';
  static const String showroomCreate = 'showroom.create';
  static const String showroomEdit = 'showroom.edit';

  /// Users
  static const String usersView = 'users.view';
  static const String usersCreate = 'users.create';
  static const String usersEdit = 'users.edit';
  static const String usersDelete = 'users.delete';

  /// Roles
  static const String rolesView = 'roles.view';
  static const String rolesManage = 'roles.manage';

  /// Products
  static const String productsView = 'products.view';
  static const String productsCreate = 'products.create';
  static const String productsEdit = 'products.edit';
  static const String productsDelete = 'products.delete';

  /// Inventory
  static const String inventoryView = 'inventory.view';
  static const String inventoryCreate = 'inventory.create';
  static const String inventoryEdit = 'inventory.edit';
  static const String inventoryTransfer = 'inventory.transfer';
  static const String inventoryAdjust = 'inventory.adjust';
  static const String inventoryReserve = 'inventory.reserve';
  static const String inventoryRelease = 'inventory.release';
  static const String inventoryDelete = 'inventory.delete';

  /// Customers
  static const String customersView = 'customers.view';
  static const String customersCreate = 'customers.create';
  static const String customersEdit = 'customers.edit';
  static const String customersDelete = 'customers.delete';
  static const String customersExport = 'customers.export';

  /// Sales
  static const String salesView = 'sales.view';
  static const String salesCreate = 'sales.create';
  static const String salesEdit = 'sales.edit';
  static const String salesCancel = 'sales.cancel';
  static const String salesDiscount = 'sales.discount';
  static const String salesApprove = 'sales.approve';

  /// Billing
  static const String billingView = 'billing.view';
  static const String billingCreate = 'billing.create';
  static const String billingEdit = 'billing.edit';
  static const String billingCancel = 'billing.cancel';
  static const String billingPrint = 'billing.print';
  static const String billingExport = 'billing.export';

  /// Payments
  static const String paymentsView = 'payments.view';
  static const String paymentsCreate = 'payments.create';
  static const String paymentsEdit = 'payments.edit';
  static const String paymentsCancel = 'payments.cancel';

  /// Finance
  static const String financeView = 'finance.view';
  static const String financeCreate = 'finance.create';
  static const String financeEdit = 'finance.edit';

  /// EMI
  static const String emiView = 'emi.view';
  static const String emiCreate = 'emi.create';
  static const String emiEdit = 'emi.edit';
  static const String emiPayment = 'emi.payment';

  /// Purchases
  static const String purchasesView = 'purchases.view';
  static const String purchasesCreate = 'purchases.create';
  static const String purchasesEdit = 'purchases.edit';
  static const String purchasesDelete = 'purchases.delete';

  /// Expenses
  static const String expensesView = 'expenses.view';
  static const String expensesCreate = 'expenses.create';
  static const String expensesEdit = 'expenses.edit';
  static const String expensesApprove = 'expenses.approve';
  static const String expensesDelete = 'expenses.delete';

  /// Accounting
  static const String accountingView = 'accounting.view';
  static const String accountingEdit = 'accounting.edit';
  static const String accountingCreate = 'accounting.create';

  /// Service
  static const String serviceView = 'service.view';
  static const String serviceCreate = 'service.create';
  static const String serviceEdit = 'service.edit';
  static const String serviceComplete = 'service.complete';
  static const String serviceBill = 'service.bill';
  static const String serviceDiscount = 'service.discount';

  /// Warranty
  static const String warrantyView = 'warranty.view';
  static const String warrantyCreate = 'warranty.create';
  static const String warrantyEdit = 'warranty.edit';

  /// Insurance
  static const String insuranceView = 'insurance.view';
  static const String insuranceCreate = 'insurance.create';
  static const String insuranceEdit = 'insurance.edit';

  /// Reminders
  static const String remindersView = 'reminders.view';
  static const String remindersCreate = 'reminders.create';
  static const String remindersEdit = 'reminders.edit';

  /// Notifications
  static const String notificationsView = 'notifications.view';

  /// Reports
  static const String reportsView = 'reports.view';
  static const String reportsExport = 'reports.export';

  /// Documents
  static const String documentsView = 'documents.view';
  static const String documentsUpload = 'documents.upload';
  static const String documentsDelete = 'documents.delete';

  /// Audit
  static const String auditView = 'audit.view';

  /// Settings
  static const String settingsView = 'settings.view';
  static const String settingsEdit = 'settings.edit';
}

/// The complete set of (module, action) permission pairs seeded into the
/// database (mirrors migration 008_roles_permissions.sql).
class PermissionCatalog {
  PermissionCatalog._();

  /// `module: [actions]`.
  static const Map<String, List<String>> catalog = <String, List<String>>{
    PermissionModules.dashboard: <String>[PermissionActions.view],
    PermissionModules.showroom: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
    ],
    PermissionModules.users: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.delete,
    ],
    PermissionModules.roles: <String>[
      PermissionActions.view,
      PermissionActions.manage,
    ],
    PermissionModules.products: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.delete,
    ],
    PermissionModules.inventory: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.transfer,
      PermissionActions.adjust,
      PermissionActions.reserve,
      PermissionActions.release,
      PermissionActions.delete,
    ],
    PermissionModules.customers: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.delete,
      PermissionActions.export,
    ],
    PermissionModules.sales: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.cancel,
      PermissionActions.discount,
      PermissionActions.approve,
    ],
    PermissionModules.billing: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.cancel,
      PermissionActions.print,
      PermissionActions.export,
    ],
    PermissionModules.payments: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.cancel,
    ],
    PermissionModules.finance: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
    ],
    PermissionModules.emi: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.payment,
    ],
    PermissionModules.purchases: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.delete,
    ],
    PermissionModules.expenses: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.approve,
      PermissionActions.delete,
    ],
    PermissionModules.accounting: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
    ],
    PermissionModules.service: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
      PermissionActions.complete,
      PermissionActions.bill,
      PermissionActions.discount,
    ],
    PermissionModules.warranty: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
    ],
    PermissionModules.insurance: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
    ],
    PermissionModules.reminders: <String>[
      PermissionActions.view,
      PermissionActions.create,
      PermissionActions.edit,
    ],
    PermissionModules.notifications: <String>[
      PermissionActions.view,
    ],
    PermissionModules.reports: <String>[
      PermissionActions.view,
      PermissionActions.export,
    ],
    PermissionModules.documents: <String>[
      PermissionActions.view,
      PermissionActions.upload,
      PermissionActions.delete,
    ],
    PermissionModules.audit: <String>[PermissionActions.view],
    PermissionModules.settings: <String>[
      PermissionActions.view,
      PermissionActions.edit,
    ],
  };

  /// Every `module.action` string in the catalog.
  static List<String> get allPermissions {
    return catalog.entries
        .expand(
          (e) => e.value.map((action) => Permissions.of(e.key, action)),
        )
        .toList(growable: false);
  }
}
