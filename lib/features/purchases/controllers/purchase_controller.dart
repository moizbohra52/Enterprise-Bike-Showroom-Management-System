import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/purchases/models/purchase_models.dart';
import 'package:enterprise_bike_showroom/features/purchases/repositories/purchase_repository.dart';
import 'package:enterprise_bike_showroom/features/products/models/product_models.dart';
import 'package:enterprise_bike_showroom/features/products/repositories/product_repository.dart';

/// Supplier list controller.
class SupplierController extends BaseListController<SupplierModel> {
  SupplierController(PurchaseRepository repository)
      : super(repository.listSuppliers, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }

  Future<void> save(SupplierModel supplier, {String? id}) async {
    if (id != null) {
      await repository.updateSupplier(id, supplier.toJson());
    } else {
      await repository.createSupplier(supplier.toJson());
    }
  }

  Future<bool> deactivate(SupplierModel supplier) async {
    try {
      await repository.deactivateSupplier(supplier.id!);
      return true;
    } on AppException {
      return false;
    }
  }
}

/// Purchase register.
class PurchaseController extends BaseListController<PurchaseModel> {
  PurchaseController(PurchaseRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }
}

/// Purchase form (supplier + lines).
class PurchaseFormController extends GetxController {
  PurchaseFormController(this.repository, this.session, this.productsRepo);

  final PurchaseRepository repository;
  final SessionController session;
  final ProductRepository productsRepo;

  /// Active products for the line picker.
  final RxList<ProductModel> products = <ProductModel>[].obs;

  final RxList<Map<String, dynamic>> suppliers = <Map<String, dynamic>>[].obs;
  final Rx<String?> supplierId = Rx<String?>(null);
  final Rx<DateTime?> orderDate = Rx<DateTime?>(null);
  final Rx<DateTime?> expectedDate = Rx<DateTime?>(null);
  final Rx<num> discount = 0.obs;
  final Rx<String> notes = ''.obs;

  final RxList<Map<String, dynamic>> lines = <Map<String, dynamic>>[].obs;

  final Rx<num> total = 0.obs;
  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  Future<void> init() async {
    await Future.wait<void>(<Future<void>>[
      loadSuppliers(),
      loadProducts(),
    ]);
  }

  Future<void> loadSuppliers() async {
    try {
      suppliers.assignAll(await repository.activeSuppliers());
    } on AppException {
      // Suppliers stay empty; the form will show a clear error on submit.
    }
  }

  Future<void> loadProducts() async {
    try {
      final PaginatedResponse<ProductModel> page =
          await productsRepo.list(PageQuery(pageSize: 200));
      products.assignAll(page.items);
    } on AppException {
      // Product list is optional context; lines can still be added.
    }
  }

  void addLine({required String productId, required String productName,
      String color = '', num qty = 1, num unitCost = 0}) {
    lines.add(<String, dynamic>{
      'product_id': productId,
      'product_name': productName,
      'color': color,
      'qty': qty,
      'unit_cost': unitCost,
    });
    _recalc();
  }

  void updateLine(int index, {num? qty, num? unitCost}) {
    if (index < 0 || index >= lines.value.length) return;
    final Map<String, dynamic> line = Map<String, dynamic>.from(lines.value[index]);
    if (qty != null) line['qty'] = qty;
    if (unitCost != null) line['unit_cost'] = unitCost;
    lines.value[index] = line;
    lines.refresh();
    _recalc();
  }

  void removeLine(int index) {
    if (index >= 0 && index < lines.value.length) {
      lines.removeAt(index);
      _recalc();
    }
  }

  void _recalc() {
    num sum = 0;
    for (final Map<String, dynamic> line in lines.value) {
      sum += SafeJson.asMoney(line['qty']) * SafeJson.asMoney(line['unit_cost']);
    }
    total.value = (sum - discount.value) < 0 ? 0 : (sum - discount.value);
  }

  Future<bool> submit() async {
    error.value = '';
    final String? supplier = supplierId.value;
    if (supplier == null) {
      error.value = 'Select a supplier.';
      return false;
    }
    if (lines.value.isEmpty) {
      error.value = 'Add at least one line.';
      return false;
    }
    if (session.activeShowroomId.isEmpty) {
      error.value = 'Select an active showroom first.';
      return false;
    }
    saving.value = true;
    try {
      await repository.create(
        supplierId: supplier,
        showroomId: session.activeShowroomId,
        lines: <Map<String, dynamic>>[
          for (int i = 0; i < lines.value.length; i++)
            <String, dynamic>{
              'product_id': lines.value[i]['product_id'],
              'product_name': lines.value[i]['product_name'],
              'color': lines.value[i]['color']?.toString() ?? '',
              'qty': lines.value[i]['qty'],
              'unit_cost': lines.value[i]['unit_cost'],
              'line_number': i + 1,
            },
        ],
        orderDate: orderDate.value,
        expectedDate: expectedDate.value,
        discount: discount.value,
        notes: notes.value.trim().isEmpty ? null : notes.value.trim(),
      );
      return true;
    } on AppException catch (e) {
      error.value = e.message;
      return false;
    } finally {
      saving.value = false;
    }
  }
}

/// Purchase details: lines + receive + pay.
class PurchaseDetailsController extends GetxController {
  PurchaseDetailsController(this.repository);

  final PurchaseRepository repository;

  final Rx<PurchaseModel?> purchase = Rx<PurchaseModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool busy = false.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      purchase.value = await repository.getById(id);
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> receive({Map<String, dynamic>? chassisByLine}) async {
    final PurchaseModel? current = purchase.value;
    if (current?.id == null) return false;
    busy.value = true;
    try {
      await repository.receive(current!.id!, chassisByLine: chassisByLine);
      await load(current.id!);
      return true;
    } on AppException {
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> pay(num amount, String mode, {String? referenceNumber}) async {
    final PurchaseModel? current = purchase.value;
    if (current?.id == null) return false;
    busy.value = true;
    try {
      await repository.pay(
        purchaseId: current!.id!,
        amount: amount,
        paymentMode: mode,
        referenceNumber: referenceNumber,
      );
      await load(current.id!);
      return true;
    } on AppException {
      return false;
    } finally {
      busy.value = false;
    }
  }
}
