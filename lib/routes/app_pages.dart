import 'package:enterprise_bike_showroom/common/views/forbidden_view.dart';
import 'package:enterprise_bike_showroom/common/views/module_pending_view.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/features/accounting/bindings/accounting_binding.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/account_form_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/account_list_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/journal_details_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/journal_list_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/manual_entry_view.dart';
import 'package:enterprise_bike_showroom/features/auth/bindings/auth_binding.dart';
import 'package:enterprise_bike_showroom/features/auth/views/forgot_password_view.dart';
import 'package:enterprise_bike_showroom/features/auth/views/login_view.dart';
import 'package:enterprise_bike_showroom/features/auth/views/reset_password_view.dart';
import 'package:enterprise_bike_showroom/features/auth/views/splash_view.dart';
import 'package:enterprise_bike_showroom/features/billing/bindings/invoice_binding.dart';
import 'package:enterprise_bike_showroom/features/billing/views/invoice_details_view.dart';
import 'package:enterprise_bike_showroom/features/billing/views/invoice_list_view.dart';
import 'package:enterprise_bike_showroom/features/customers/bindings/customer_binding.dart';
import 'package:enterprise_bike_showroom/features/customers/views/customer_details_view.dart';
import 'package:enterprise_bike_showroom/features/customers/views/customer_form_view.dart';
import 'package:enterprise_bike_showroom/features/customers/views/customer_list_view.dart';
import 'package:enterprise_bike_showroom/features/customers/views/vehicle_details_view.dart';
import 'package:enterprise_bike_showroom/features/dashboard/bindings/dashboard_binding.dart';
import 'package:enterprise_bike_showroom/features/dashboard/views/dashboard_view.dart';
import 'package:enterprise_bike_showroom/features/documents/bindings/document_binding.dart';
import 'package:enterprise_bike_showroom/features/documents/views/audit_log_view.dart';
import 'package:enterprise_bike_showroom/features/documents/views/document_list_view.dart';
import 'package:enterprise_bike_showroom/features/expenses/bindings/expense_binding.dart';
import 'package:enterprise_bike_showroom/features/expenses/views/expense_details_view.dart';
import 'package:enterprise_bike_showroom/features/expenses/views/expense_form_view.dart';
import 'package:enterprise_bike_showroom/features/expenses/views/expense_list_view.dart';
import 'package:enterprise_bike_showroom/features/finance/bindings/loan_binding.dart';
import 'package:enterprise_bike_showroom/features/finance/views/loan_details_view.dart';
import 'package:enterprise_bike_showroom/features/finance/views/loan_list_view.dart';
import 'package:enterprise_bike_showroom/features/freeservice/bindings/free_service_binding.dart';
import 'package:enterprise_bike_showroom/features/freeservice/views/free_service_view.dart';
import 'package:enterprise_bike_showroom/features/insurance/bindings/insurance_binding.dart';
import 'package:enterprise_bike_showroom/features/insurance/views/insurance_details_view.dart';
import 'package:enterprise_bike_showroom/features/insurance/views/insurance_form_view.dart';
import 'package:enterprise_bike_showroom/features/insurance/views/insurance_list_view.dart';
import 'package:enterprise_bike_showroom/features/inventory/bindings/inventory_binding.dart';
import 'package:enterprise_bike_showroom/features/inventory/views/inventory_details_view.dart';
import 'package:enterprise_bike_showroom/features/inventory/views/inventory_list_view.dart';
import 'package:enterprise_bike_showroom/features/inventory/views/stock_adjust_view.dart';
import 'package:enterprise_bike_showroom/features/inventory/views/stock_in_view.dart';
import 'package:enterprise_bike_showroom/features/inventory/views/stock_transfer_view.dart';
import 'package:enterprise_bike_showroom/features/notifications/views/notification_list_view.dart';
import 'package:enterprise_bike_showroom/features/payments/bindings/payment_binding.dart';
import 'package:enterprise_bike_showroom/features/payments/views/payment_details_view.dart';
import 'package:enterprise_bike_showroom/features/payments/views/payment_form_view.dart';
import 'package:enterprise_bike_showroom/features/payments/views/payment_list_view.dart';
import 'package:enterprise_bike_showroom/features/products/bindings/product_binding.dart';
import 'package:enterprise_bike_showroom/features/products/views/product_details_view.dart';
import 'package:enterprise_bike_showroom/features/products/views/product_form_view.dart';
import 'package:enterprise_bike_showroom/features/products/views/product_list_view.dart';
import 'package:enterprise_bike_showroom/features/purchases/bindings/purchase_binding.dart';
import 'package:enterprise_bike_showroom/features/purchases/views/purchase_details_view.dart';
import 'package:enterprise_bike_showroom/features/purchases/views/purchase_form_view.dart';
import 'package:enterprise_bike_showroom/features/purchases/views/purchase_list_view.dart';
import 'package:enterprise_bike_showroom/features/purchases/views/supplier_form_view.dart';
import 'package:enterprise_bike_showroom/features/purchases/views/supplier_list_view.dart';
import 'package:enterprise_bike_showroom/features/reminders/bindings/reminder_binding.dart';
import 'package:enterprise_bike_showroom/features/reminders/views/reminder_form_view.dart';
import 'package:enterprise_bike_showroom/features/reminders/views/reminder_list_view.dart';
import 'package:enterprise_bike_showroom/features/reports/bindings/report_binding.dart';
import 'package:enterprise_bike_showroom/features/reports/views/report_catalog_view.dart';
import 'package:enterprise_bike_showroom/features/reports/views/report_view.dart';
import 'package:enterprise_bike_showroom/features/sales/bindings/sale_binding.dart';
import 'package:enterprise_bike_showroom/features/sales/views/sale_details_view.dart';
import 'package:enterprise_bike_showroom/features/sales/views/sale_form_view.dart';
import 'package:enterprise_bike_showroom/features/sales/views/sale_list_view.dart';
import 'package:enterprise_bike_showroom/features/service/bindings/service_binding.dart';
import 'package:enterprise_bike_showroom/features/service/views/service_details_view.dart';
import 'package:enterprise_bike_showroom/features/service/views/service_form_view.dart';
import 'package:enterprise_bike_showroom/features/service/views/service_list_view.dart';
import 'package:enterprise_bike_showroom/features/settings/views/settings_view.dart';
import 'package:enterprise_bike_showroom/features/showroom/bindings/showroom_binding.dart';
import 'package:enterprise_bike_showroom/features/showroom/views/showroom_details_view.dart';
import 'package:enterprise_bike_showroom/features/showroom/views/showroom_form_view.dart';
import 'package:enterprise_bike_showroom/features/showroom/views/showroom_list_view.dart';
import 'package:enterprise_bike_showroom/features/users/bindings/users_binding.dart';
import 'package:enterprise_bike_showroom/features/users/views/user_form_view.dart';
import 'package:enterprise_bike_showroom/features/users/views/users_view.dart';
import 'package:enterprise_bike_showroom/features/warranty/bindings/warranty_binding.dart';
import 'package:enterprise_bike_showroom/features/warranty/views/warranty_details_view.dart';
import 'package:enterprise_bike_showroom/features/warranty/views/warranty_list_view.dart';
import 'package:enterprise_bike_showroom/routes/app_middleware.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The centralized route table.
///
/// Every route declared in [AppRoutes] is registered: implemented screens use
/// their feature view + binding, screens that do not exist yet render
/// [ModulePendingView] so navigation never dead-ends. Protected routes carry
/// [AuthMiddleware] (session) and, where a module permission applies,
/// [PermissionMiddleware].
class AppPages {
  AppPages._();

  /// Route shown when the app starts.
  static const String initial = AppRoutes.splash;

  /// All pages, in navigation order.
  static final List<GetPage<dynamic>> pages = <GetPage<dynamic>>[
    ..._publicPages,
    ..._overviewPages,
    ..._administrationPages,
    ..._catalogPages,
    ..._customerPages,
    ..._salesPages,
    ..._financePages,
    ..._operationsPages,
    ..._afterSalesPages,
    ..._insightPages,
  ];

  // ------------------------------------------------------------- guards

  static List<GetMiddleware> get _auth => <GetMiddleware>[AuthMiddleware()];

  static List<GetMiddleware> _guard(String permission) => <GetMiddleware>[
        AuthMiddleware(),
        PermissionMiddleware(permission),
      ];

  static GetPage<dynamic> _page(
    String name,
    Widget Function() page, {
    Bindings? binding,
    List<GetMiddleware>? middlewares,
  }) {
    return GetPage<dynamic>(
      name: name,
      page: page,
      binding: binding,
      middlewares: middlewares ?? const <GetMiddleware>[],
    );
  }

  /// A declared route whose screen has not been built yet.
  static GetPage<dynamic> _pending(String name, String label) {
    return _page(
      name,
      () => ModulePendingView(module: label),
      middlewares: _auth,
    );
  }

  // -------------------------------------------------------------- public

  static final List<GetPage<dynamic>> _publicPages = <GetPage<dynamic>>[
    _page(AppRoutes.splash, () => const SplashView()),
    _page(
      AppRoutes.login,
      () => const LoginView(),
      binding: AuthBinding(),
    ),
    _page(
      AppRoutes.forgotPassword,
      () => const ForgotPasswordView(),
      binding: AuthBinding(),
    ),
    _page(
      AppRoutes.resetPassword,
      () => const ResetPasswordView(),
      binding: AuthBinding(),
    ),
    _page(
      AppRoutes.forbidden,
      () => const ForbiddenView(),
      middlewares: _auth,
    ),
  ];

  // ------------------------------------------------------------ overview

  static final List<GetPage<dynamic>> _overviewPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.dashboard,
      () => const DashboardView(),
      binding: DashboardBinding(),
      middlewares: _auth,
    ),
    _page(
      AppRoutes.settings,
      () => const SettingsView(),
      binding: BindingsBuilder(ShowroomBinding().dependencies),
      middlewares: _auth,
    ),
  ];

  // ------------------------------------------------------ administration

  static final List<GetPage<dynamic>> _administrationPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.showrooms,
      () => const ShowroomListView(),
      binding: ShowroomBinding(),
      middlewares: _guard(Permissions.showroomView),
    ),
    _page(
      AppRoutes.showroomForm,
      () => ShowroomFormView(),
      binding: ShowroomBinding(),
      middlewares: _guard(Permissions.showroomView),
    ),
    _page(
      AppRoutes.showroomDetails,
      () => const ShowroomDetailsView(),
      binding: ShowroomBinding(),
      middlewares: _guard(Permissions.showroomView),
    ),
    _page(
      AppRoutes.users,
      () => const UsersView(),
      binding: UsersBinding(),
      middlewares: _guard(Permissions.usersView),
    ),
    _page(
      AppRoutes.userForm,
      () => const UserFormView(),
      binding: UsersBinding(),
      middlewares: _guard(Permissions.usersView),
    ),
    _page(
      AppRoutes.userDetails,
      () => const UserFormView(),
      binding: UsersBinding(),
      middlewares: _guard(Permissions.usersView),
    ),
    _pending(AppRoutes.roles, 'Roles & Permissions'),
    _pending(AppRoutes.rolePermissions, 'Role Permissions'),
  ];

  // ------------------------------------------------------------- catalog

  static final List<GetPage<dynamic>> _catalogPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.products,
      () => const ProductListView(),
      binding: ProductBinding(),
      middlewares: _guard(Permissions.productsView),
    ),
    _page(
      AppRoutes.productForm,
      () => ProductFormView(),
      binding: ProductBinding(),
      middlewares: _guard(Permissions.productsView),
    ),
    _page(
      AppRoutes.productDetails,
      () => const ProductDetailsView(),
      binding: ProductBinding(),
      middlewares: _guard(Permissions.productsView),
    ),
    _page(
      AppRoutes.inventory,
      () => const InventoryListView(),
      binding: InventoryBinding(),
      middlewares: _guard(Permissions.inventoryView),
    ),
    _page(
      AppRoutes.inventoryDetails,
      () => const InventoryDetailsView(),
      binding: InventoryBinding(),
      middlewares: _guard(Permissions.inventoryView),
    ),
    _page(
      AppRoutes.stockIn,
      () => StockInView(),
      binding: InventoryBinding(),
      middlewares: _guard(Permissions.inventoryCreate),
    ),
    _page(
      AppRoutes.stockTransfer,
      () => StockTransferView(),
      binding: InventoryBinding(),
      middlewares: _guard(Permissions.inventoryTransfer),
    ),
    _page(
      AppRoutes.stockAdjust,
      () => StockAdjustView(),
      binding: InventoryBinding(),
      middlewares: _guard(Permissions.inventoryAdjust),
    ),
    _page(
      AppRoutes.purchases,
      () => const PurchaseListView(),
      binding: PurchaseBinding(),
      middlewares: _guard(Permissions.purchasesView),
    ),
    _page(
      AppRoutes.purchaseForm,
      () => const PurchaseFormView(),
      binding: PurchaseBinding(),
      middlewares: _guard(Permissions.purchasesView),
    ),
    _page(
      AppRoutes.purchaseDetails,
      () => const PurchaseDetailsView(),
      binding: PurchaseBinding(),
      middlewares: _guard(Permissions.purchasesView),
    ),
    _page(
      AppRoutes.suppliers,
      () => const SupplierListView(),
      binding: PurchaseBinding(),
      middlewares: _guard(Permissions.purchasesView),
    ),
    _page(
      AppRoutes.supplierForm,
      () => SupplierFormView(),
      binding: PurchaseBinding(),
      middlewares: _guard(Permissions.purchasesView),
    ),
  ];

  // ----------------------------------------------------------- customers

  static final List<GetPage<dynamic>> _customerPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.customers,
      () => const CustomerListView(),
      binding: CustomerBinding(),
      middlewares: _guard(Permissions.customersView),
    ),
    _page(
      AppRoutes.customerForm,
      () => CustomerFormView(),
      binding: CustomerBinding(),
      middlewares: _guard(Permissions.customersView),
    ),
    _page(
      AppRoutes.customerDetails,
      () => const CustomerDetailsView(),
      binding: CustomerBinding(),
      middlewares: _guard(Permissions.customersView),
    ),
    _page(
      AppRoutes.vehicleDetails,
      () => const VehicleDetailsView(),
      binding: CustomerBinding(),
      middlewares: _guard(Permissions.customersView),
    ),
    _pending(AppRoutes.vehicleForm, 'Vehicle'),
  ];

  // --------------------------------------------------------------- sales

  static final List<GetPage<dynamic>> _salesPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.sales,
      () => const SaleListView(),
      binding: SaleBinding(),
      middlewares: _guard(Permissions.salesView),
    ),
    _page(
      AppRoutes.saleForm,
      () => const SaleFormView(),
      binding: SaleBinding(),
      middlewares: _guard(Permissions.salesCreate),
    ),
    _page(
      AppRoutes.saleDetails,
      () => const SaleDetailsView(),
      binding: SaleBinding(),
      middlewares: _guard(Permissions.salesView),
    ),
    _page(
      AppRoutes.billing,
      () => const InvoiceListView(),
      binding: InvoiceBinding(),
      middlewares: _guard(Permissions.billingView),
    ),
    _page(
      AppRoutes.invoiceDetails,
      () => const InvoiceDetailsView(),
      binding: InvoiceBinding(),
      middlewares: _guard(Permissions.billingView),
    ),
    _pending(AppRoutes.invoiceForm, 'Invoice'),
    _page(
      AppRoutes.payments,
      () => const PaymentListView(),
      binding: PaymentBinding(),
      middlewares: _guard(Permissions.paymentsView),
    ),
    _page(
      AppRoutes.paymentForm,
      () => PaymentFormView(),
      binding: PaymentBinding(),
      middlewares: _guard(Permissions.paymentsCreate),
    ),
    _page(
      AppRoutes.paymentDetails,
      () => const PaymentDetailsView(),
      binding: PaymentBinding(),
      middlewares: _guard(Permissions.paymentsView),
    ),
  ];

  // ------------------------------------------------------------- finance

  static final List<GetPage<dynamic>> _financePages = <GetPage<dynamic>>[
    _page(
      AppRoutes.finance,
      () => const LoanListView(),
      binding: LoanBinding(),
      middlewares: _guard(Permissions.financeView),
    ),
    _page(
      AppRoutes.loans,
      () => const LoanListView(),
      binding: LoanBinding(),
      middlewares: _guard(Permissions.financeView),
    ),
    _page(
      AppRoutes.loanDetails,
      () => const LoanDetailsView(),
      binding: LoanBinding(),
      middlewares: _guard(Permissions.financeView),
    ),
    _pending(AppRoutes.financeCompanyForm, 'Finance Company'),
    _pending(AppRoutes.loanForm, 'Loan'),
    _page(
      AppRoutes.emi,
      () => const LoanListView(),
      binding: LoanBinding(),
      middlewares: _guard(Permissions.emiView),
    ),
    _pending(AppRoutes.emiSchedule, 'EMI Schedule'),
    _pending(AppRoutes.emiPayment, 'EMI Payment'),
    _page(
      AppRoutes.expenses,
      () => const ExpenseListView(),
      binding: ExpenseBinding(),
      middlewares: _guard(Permissions.expensesView),
    ),
    _page(
      AppRoutes.expenseForm,
      () => const ExpenseFormView(),
      binding: ExpenseBinding(),
      middlewares: _guard(Permissions.expensesCreate),
    ),
    _page(
      AppRoutes.expenseDetails,
      () => const ExpenseDetailsView(),
      binding: ExpenseBinding(),
      middlewares: _guard(Permissions.expensesView),
    ),
    _page(
      AppRoutes.accounting,
      () => const AccountListView(),
      binding: AccountingBinding(),
      middlewares: _guard(Permissions.accountingView),
    ),
    _page(
      AppRoutes.accountForm,
      () => const AccountFormView(),
      binding: AccountingBinding(),
      middlewares: _guard(Permissions.accountingView),
    ),
    _page(
      AppRoutes.accountingManualEntry,
      () => const ManualEntryView(),
      binding: AccountingBinding(),
      middlewares: _guard(Permissions.accountingView),
    ),
    _page(
      AppRoutes.accountingTransactions,
      () => const JournalListView(),
      binding: AccountingBinding(),
      middlewares: _guard(Permissions.accountingView),
    ),
    _page(
      AppRoutes.accountingTransactionDetails,
      () => const JournalDetailsView(),
      binding: AccountingBinding(),
      middlewares: _guard(Permissions.accountingView),
    ),
  ];

  // ---------------------------------------------------------- operations

  static final List<GetPage<dynamic>> _operationsPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.reminders,
      () => const ReminderListView(),
      binding: ReminderBinding(),
      middlewares: _guard(Permissions.remindersView),
    ),
    _page(
      AppRoutes.remindersForm,
      () => const ReminderFormView(),
      binding: ReminderBinding(),
      middlewares: _guard(Permissions.remindersView),
    ),
    _page(
      AppRoutes.notifications,
      () => const NotificationListView(),
      middlewares: _auth,
    ),
    _page(
      AppRoutes.documents,
      () => const DocumentListView(),
      binding: DocumentBinding(),
      middlewares: _guard(Permissions.documentsView),
    ),
    _page(
      AppRoutes.audit,
      () => const AuditLogView(),
      binding: DocumentBinding(),
      middlewares: _guard(Permissions.auditView),
    ),
  ];

  // --------------------------------------------------------- after sales

  static final List<GetPage<dynamic>> _afterSalesPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.service,
      () => const ServiceListView(),
      binding: ServiceBinding(),
      middlewares: _guard(Permissions.serviceView),
    ),
    _page(
      AppRoutes.serviceForm,
      () => const ServiceFormView(),
      binding: ServiceBinding(),
      middlewares: _guard(Permissions.serviceCreate),
    ),
    _page(
      AppRoutes.serviceDetails,
      () => const ServiceDetailsView(),
      binding: ServiceBinding(),
      middlewares: _guard(Permissions.serviceView),
    ),
    _page(
      AppRoutes.freeService,
      () => const FreeServiceView(),
      binding: FreeServiceBinding(),
      middlewares: _guard(Permissions.serviceView),
    ),
    _pending(AppRoutes.freeServicePlans, 'Free Service Plans'),
    _page(
      AppRoutes.warranty,
      () => const WarrantyListView(),
      binding: WarrantyBinding(),
      middlewares: _guard(Permissions.warrantyView),
    ),
    _page(
      AppRoutes.warrantyDetails,
      () => const WarrantyDetailsView(),
      binding: WarrantyBinding(),
      middlewares: _guard(Permissions.warrantyView),
    ),
    _page(
      AppRoutes.insurance,
      () => const InsuranceListView(),
      binding: InsuranceBinding(),
      middlewares: _guard(Permissions.insuranceView),
    ),
    _page(
      AppRoutes.insuranceForm,
      () => const InsuranceFormView(),
      binding: InsuranceBinding(),
      middlewares: _guard(Permissions.insuranceView),
    ),
    _page(
      AppRoutes.insuranceDetails,
      () => const InsuranceDetailsView(),
      binding: InsuranceBinding(),
      middlewares: _guard(Permissions.insuranceView),
    ),
  ];

  // ------------------------------------------------------------- insights

  static final List<GetPage<dynamic>> _insightPages = <GetPage<dynamic>>[
    _page(
      AppRoutes.reports,
      () => const ReportCatalogView(),
      binding: ReportBinding(),
      middlewares: _guard(Permissions.reportsView),
    ),
    _page(
      AppRoutes.report,
      () => const ReportView(),
      binding: ReportBinding(),
      middlewares: _guard(Permissions.reportsView),
    ),
  ];
}
