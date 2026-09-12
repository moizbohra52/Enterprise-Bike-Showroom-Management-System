import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/routing/route_guard.dart';
import 'package:enterprise_bike_showroom/common/views/not_found_view.dart';
import 'package:enterprise_bike_showroom/core/constants/permission_constants.dart';
import 'package:enterprise_bike_showroom/features/accounting/bindings/accounting_binding.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/account_form_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/account_list_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/journal_details_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/journal_list_view.dart';
import 'package:enterprise_bike_showroom/features/accounting/views/manual_entry_view.dart';
import 'package:enterprise_bike_showroom/features/auth/bindings/auth_binding.dart';
import 'package:enterprise_bike_showroom/features/auth/views/forbidden_view.dart';
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
import 'package:enterprise_bike_showroom/features/search/views/global_search_view.dart';
import 'package:enterprise_bike_showroom/features/service/bindings/service_binding.dart';
import 'package:enterprise_bike_showroom/features/service/views/service_details_view.dart';
import 'package:enterprise_bike_showroom/features/service/views/service_form_view.dart';
import 'package:enterprise_bike_showroom/features/service/views/service_list_view.dart';
import 'package:enterprise_bike_showroom/features/settings/views/settings_view.dart';
import 'package:enterprise_bike_showroom/features/showroom/bindings/showroom_binding.dart';
import 'package:enterprise_bike_showroom/features/showroom/views/showroom_details_view.dart';
import 'package:enterprise_bike_showroom/features/showroom/views/showroom_form_view.dart';
import 'package:enterprise_bike_showroom/features/showroom/views/showroom_list_view.dart';
import 'package:enterprise_bike_showroom/features/warranty/bindings/warranty_binding.dart';
import 'package:enterprise_bike_showroom/features/warranty/views/warranty_details_view.dart';
import 'package:enterprise_bike_showroom/features/warranty/views/warranty_list_view.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Runs several module bindings for one route.
///
/// Needed where a page reads a repository owned by another module (purchase
/// forms pick products) or where a page needs `AuthController` outside the
/// auth flow (the profile menu signs out from Settings).
class CompositeBinding extends Bindings {
  CompositeBinding(this.bindings);

  final List<Bindings> bindings;

  @override
  void dependencies() {
    for (final Bindings binding in bindings) {
      binding.dependencies();
    }
  }
}

/// The route table: every `AppRoutes` constant that has a page.
///
/// Convention:
/// - `name` may end with `/:id?` so both `/x/details/<id>` (path) and
///   `/x/details?id=<id>` (query, used by controllers) resolve;
/// - protected pages are wrapped in [RouteGuard] with the module `*.view`
///   permission;
/// - module `Bindings` provide repositories + controllers lazily.
class AppPages {
  AppPages._();

  /// First route shown by `GetMaterialApp`.
  static const String initial = AppRoutes.splash;

  static final List<GetPage<dynamic>> pages = <GetPage<dynamic>>[
    // ------------------------------------------------------------------ auth
    _page(
      name: AppRoutes.splash,
      builder: () => const SplashView(),
      binding: AuthBinding(),
      allowUnauthenticated: true,
      transition: Transition.fadeIn,
    ),
    _page(
      name: AppRoutes.login,
      builder: () => const LoginView(),
      binding: AuthBinding(),
      allowUnauthenticated: true,
      transition: Transition.fadeIn,
    ),
    _page(
      name: AppRoutes.forgotPassword,
      builder: () => const ForgotPasswordView(),
      binding: AuthBinding(),
      allowUnauthenticated: true,
      transition: Transition.fadeIn,
    ),
    _page(
      name: AppRoutes.resetPassword,
      builder: () => const ResetPasswordView(),
      binding: AuthBinding(),
      allowUnauthenticated: true,
      transition: Transition.fadeIn,
    ),

    // ----------------------------------------------------------------- shell
    _page(
      name: AppRoutes.dashboard,
      builder: () => const DashboardView(),
      binding: DashboardBinding(),
      permission: Permissions.dashboardView,
    ),
    _page(
      // Available to every signed-in user: the top bar offers search on all
      // screens, so it is guarded by authentication only.
      name: AppRoutes.search,
      builder: () => const GlobalSearchView(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.forbidden,
      page: () => ForbiddenView(permission: _argumentPermission()),
      transition: Transition.fadeIn,
    ),

    // -------------------------------------------------------------- showrooms
    _page(
      name: AppRoutes.showrooms,
      builder: () => const ShowroomListView(),
      binding: ShowroomBinding(),
      permission: Permissions.showroomView,
    ),
    _page(
      name: '${AppRoutes.showroomForm}/:id?',
      builder: () => const ShowroomFormView(),
      binding: ShowroomBinding(),
      permission: Permissions.showroomView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.showroomDetails}/:id?',
      builder: () => const ShowroomDetailsView(),
      binding: ShowroomBinding(),
      permission: Permissions.showroomView,
      transition: Transition.rightToLeft,
    ),

    // --------------------------------------------------------------- products
    _page(
      name: AppRoutes.products,
      builder: () => const ProductListView(),
      binding: ProductBinding(),
      permission: Permissions.productsView,
    ),
    _page(
      name: '${AppRoutes.productForm}/:id?',
      builder: () => const ProductFormView(),
      binding: ProductBinding(),
      permission: Permissions.productsView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.productDetails}/:id?',
      builder: () => const ProductDetailsView(),
      binding: ProductBinding(),
      permission: Permissions.productsView,
      transition: Transition.rightToLeft,
    ),

    // -------------------------------------------------------------- inventory
    _page(
      name: AppRoutes.inventory,
      builder: () => const InventoryListView(),
      binding: InventoryBinding(),
      permission: Permissions.inventoryView,
    ),
    _page(
      name: '${AppRoutes.inventoryDetails}/:id?',
      builder: () => const InventoryDetailsView(),
      binding: InventoryBinding(),
      permission: Permissions.inventoryView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.stockIn,
      builder: () => const StockInView(),
      binding: InventoryBinding(),
      permission: Permissions.inventoryView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.stockTransfer,
      builder: () => const StockTransferView(),
      binding: InventoryBinding(),
      permission: Permissions.inventoryTransfer,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.stockAdjust,
      builder: () => const StockAdjustView(),
      binding: InventoryBinding(),
      permission: Permissions.inventoryAdjust,
      transition: Transition.rightToLeft,
    ),

    // ------------------------------------------------------ customers/vehicles
    _page(
      name: AppRoutes.customers,
      builder: () => const CustomerListView(),
      binding: CustomerBinding(),
      permission: Permissions.customersView,
    ),
    _page(
      name: '${AppRoutes.customerForm}/:id?',
      builder: () => const CustomerFormView(),
      binding: CustomerBinding(),
      permission: Permissions.customersView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.customerDetails}/:id?',
      builder: () => const CustomerDetailsView(),
      binding: CustomerBinding(),
      permission: Permissions.customersView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.vehicleDetails}/:id?',
      builder: () => const VehicleDetailsView(),
      binding: CustomerBinding(),
      permission: Permissions.customersView,
      transition: Transition.rightToLeft,
    ),

    // ------------------------------------------------------------------ sales
    _page(
      name: AppRoutes.sales,
      builder: () => const SaleListView(),
      binding: SaleBinding(),
      permission: Permissions.salesView,
    ),
    _page(
      name: '${AppRoutes.saleForm}/:id?',
      builder: () => const SaleFormView(),
      binding: CompositeBinding(<Bindings>[
        const SaleBinding(),
        const CustomerBinding(),
        const InventoryBinding(),
      ]),
      permission: Permissions.salesView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.saleDetails}/:id?',
      builder: () => const SaleDetailsView(),
      binding: SaleBinding(),
      permission: Permissions.salesView,
      transition: Transition.rightToLeft,
    ),

    // ---------------------------------------------------------------- billing
    _page(
      name: AppRoutes.billing,
      builder: () => const InvoiceListView(),
      binding: InvoiceBinding(),
      permission: Permissions.billingView,
    ),
    _page(
      name: '${AppRoutes.invoiceDetails}/:id?',
      builder: () => const InvoiceDetailsView(),
      binding: InvoiceBinding(),
      permission: Permissions.billingView,
      transition: Transition.rightToLeft,
    ),

    // --------------------------------------------------------------- payments
    _page(
      name: AppRoutes.payments,
      builder: () => const PaymentListView(),
      binding: PaymentBinding(),
      permission: Permissions.paymentsView,
    ),
    _page(
      name: '${AppRoutes.paymentForm}/:id?',
      builder: () => const PaymentFormView(),
      binding: PaymentBinding(),
      permission: Permissions.paymentsView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.paymentDetails}/:id?',
      builder: () => const PaymentDetailsView(),
      binding: PaymentBinding(),
      permission: Permissions.paymentsView,
      transition: Transition.rightToLeft,
    ),

    // ----------------------------------------------------- finance / loans / emi
    _page(
      name: AppRoutes.finance,
      builder: () => const LoanListView(),
      binding: LoanBinding(),
      permission: Permissions.financeView,
    ),
    _page(
      name: AppRoutes.loans,
      builder: () => const LoanListView(),
      binding: LoanBinding(),
      permission: Permissions.financeView,
    ),
    _page(
      name: '${AppRoutes.loanDetails}/:id?',
      builder: () => const LoanDetailsView(),
      binding: LoanBinding(),
      permission: Permissions.financeView,
      transition: Transition.rightToLeft,
    ),

    // ------------------------------------------------------------ purchases
    _page(
      name: AppRoutes.purchases,
      builder: () => const PurchaseListView(),
      binding: PurchaseBinding(),
      permission: Permissions.purchasesView,
    ),
    _page(
      name: '${AppRoutes.purchaseForm}/:id?',
      builder: () => const PurchaseFormView(),
      binding: PurchaseBinding(),
      permission: Permissions.purchasesView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.purchaseDetails}/:id?',
      builder: () => const PurchaseDetailsView(),
      binding: PurchaseBinding(),
      permission: Permissions.purchasesView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.suppliers,
      builder: () => const SupplierListView(),
      binding: PurchaseBinding(),
      permission: Permissions.purchasesView,
    ),
    _page(
      name: '${AppRoutes.supplierForm}/:id?',
      builder: () => const SupplierFormView(),
      binding: PurchaseBinding(),
      permission: Permissions.purchasesView,
      transition: Transition.rightToLeft,
    ),

    // --------------------------------------------------------------- expenses
    _page(
      name: AppRoutes.expenses,
      builder: () => const ExpenseListView(),
      binding: ExpenseBinding(),
      permission: Permissions.expensesView,
    ),
    _page(
      name: '${AppRoutes.expenseForm}/:id?',
      builder: () => const ExpenseFormView(),
      binding: ExpenseBinding(),
      permission: Permissions.expensesView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.expenseDetails}/:id?',
      builder: () => const ExpenseDetailsView(),
      binding: ExpenseBinding(),
      permission: Permissions.expensesView,
      transition: Transition.rightToLeft,
    ),

    // ------------------------------------------------------------- accounting
    _page(
      name: AppRoutes.accounting,
      builder: () => const JournalListView(),
      binding: AccountingBinding(),
      permission: Permissions.accountingView,
    ),
    _page(
      name: AppRoutes.accountingTransactions,
      builder: () => const JournalListView(),
      binding: AccountingBinding(),
      permission: Permissions.accountingView,
    ),
    _page(
      name: '${AppRoutes.accountingTransactionDetails}/:id?',
      builder: () => const JournalDetailsView(),
      binding: AccountingBinding(),
      permission: Permissions.accountingView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.accountingManualEntry,
      builder: () => const ManualEntryView(),
      binding: AccountingBinding(),
      permission: Permissions.accountingEdit,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.accountForm}/:id?',
      builder: () => const AccountFormView(),
      binding: AccountingBinding(),
      permission: Permissions.accountingView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.accountingAccounts,
      builder: () => const AccountListView(),
      binding: AccountingBinding(),
      permission: Permissions.accountingView,
      transition: Transition.rightToLeft,
    ),

    // ---------------------------------------------------------------- service
    _page(
      name: AppRoutes.service,
      builder: () => const ServiceListView(),
      binding: ServiceBinding(),
      permission: Permissions.serviceView,
    ),
    _page(
      name: '${AppRoutes.serviceForm}/:id?',
      builder: () => const ServiceFormView(),
      binding: ServiceBinding(),
      permission: Permissions.serviceView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.serviceDetails}/:id?',
      builder: () => const ServiceDetailsView(),
      binding: ServiceBinding(),
      permission: Permissions.serviceView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.freeService,
      builder: () => const FreeServiceView(),
      binding: FreeServiceBinding(),
      permission: Permissions.serviceView,
    ),

    // ---------------------------------------------------- warranty/insurance
    _page(
      name: AppRoutes.warranty,
      builder: () => const WarrantyListView(),
      binding: WarrantyBinding(),
      permission: Permissions.warrantyView,
    ),
    _page(
      name: '${AppRoutes.warrantyDetails}/:id?',
      builder: () => const WarrantyDetailsView(),
      binding: WarrantyBinding(),
      permission: Permissions.warrantyView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.insurance,
      builder: () => const InsuranceListView(),
      binding: InsuranceBinding(),
      permission: Permissions.insuranceView,
    ),
    _page(
      name: '${AppRoutes.insuranceForm}/:id?',
      builder: () => const InsuranceFormView(),
      binding: InsuranceBinding(),
      permission: Permissions.insuranceView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: '${AppRoutes.insuranceDetails}/:id?',
      builder: () => const InsuranceDetailsView(),
      binding: InsuranceBinding(),
      permission: Permissions.insuranceView,
      transition: Transition.rightToLeft,
    ),

    // --------------------------------------------------- reminders & messages
    _page(
      name: AppRoutes.reminders,
      builder: () => const ReminderListView(),
      binding: ReminderBinding(),
      permission: Permissions.remindersView,
    ),
    _page(
      name: '${AppRoutes.remindersForm}/:id?',
      builder: () => const ReminderFormView(),
      binding: ReminderBinding(),
      permission: Permissions.remindersView,
      transition: Transition.rightToLeft,
    ),
    _page(
      name: AppRoutes.notifications,
      builder: () => const NotificationListView(),
      permission: Permissions.notificationsView,
    ),

    // ---------------------------------------------------------------- reports
    _page(
      name: AppRoutes.reports,
      builder: () => const ReportCatalogView(),
      binding: ReportBinding(),
      permission: Permissions.reportsView,
    ),
    _page(
      name: '${AppRoutes.report}/:key?',
      builder: () => const ReportView(),
      binding: ReportBinding(),
      permission: Permissions.reportsView,
      transition: Transition.rightToLeft,
    ),

    // --------------------------------------------------- documents & settings
    _page(
      name: AppRoutes.documents,
      builder: () => const DocumentListView(),
      binding: DocumentBinding(),
      permission: Permissions.documentsView,
    ),
    _page(
      name: AppRoutes.audit,
      builder: () => const AuditLogView(),
      binding: DocumentBinding(),
      permission: Permissions.auditView,
    ),
    _page(
      name: AppRoutes.settings,
      builder: () => const SettingsView(),
      binding: AuthBinding(),
      permission: Permissions.settingsView,
    ),
  ];

  /// Note: the Settings route also runs `AuthBinding`, because profile-menu
  /// sign-out is implemented on `AuthController` (outside the auth flow).

  /// `unknownRoute` target (route not present in [pages]).
  static GetPage<dynamic> get unknownRoute => GetPage<dynamic>(
        name: AppRoutes.notFound,
        page: () => NotFoundView(route: Get.currentRoute),
      );

  /// Builds a guarded page.
  static GetPage<dynamic> _page({
    required String name,
    required Widget Function() builder,
    Bindings? binding,
    String? permission,
    bool allowUnauthenticated = false,
    Transition? transition,
  }) {
    return GetPage<dynamic>(
      name: name,
      binding: binding,
      transition: transition,
      page: () => RouteGuard(
        permission: permission,
        allowUnauthenticated: allowUnauthenticated,
        child: builder(),
      ),
    );
  }

  /// Permission passed as route arguments by the dashboard/`RouteGuard`
  /// when sending the user to the forbidden screen.
  static String? _argumentPermission() {
    final Object? args = Get.arguments;
    return args is String ? args : null;
  }
}
