import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/features/inventory/models/inventory_models.dart';
import 'package:enterprise_bike_showroom/features/inventory/repositories/inventory_repository.dart';
import 'package:enterprise_bike_showroom/features/products/controllers/product_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Inventory list (all bikes, filterable).
class InventoryController extends BaseListController<InventoryModel> {
  InventoryController(InventoryRepository repository)
      : super(repository.list, pageSize: 20) {
    this.repository = repository;
  }

  late final InventoryRepository repository;

  @override
  Future<void> onInit() async {
    super.onInit();
    refresh();
  }

  Future<void> openDetails(InventoryModel item) async {
    await Get.toNamed(AppRoutes.inventoryDetails,
        parameters: <String, String>{'id': item.id!});
  }

  Future<void> openStockIn() async {
    await Get.toNamed(AppRoutes.stockIn);
    refresh();
  }

  Future<void> openTransfer() async {
    await Get.toNamed(AppRoutes.stockTransfer);
    refresh();
  }

  Future<void> openAdjust() async {
    await Get.toNamed(AppRoutes.stockAdjust);
    refresh();
  }

  /// Product filter options (from the products module catalog).
  List<DropdownOption<String?>> get productOptions {
    final ProductController products = Get.find<ProductController>();
    return <DropdownOption<String?>>[
      const DropdownOption<String?>(value: null, label: 'All products'),
      for (final dynamic p in products.items.value)
        if (p.id != null)
          DropdownOption<String?>(value: p.id, label: p.fullName),
    ];
  }
}

/// Inventory details (bike 360 lite: specs + history).
class InventoryDetailsController extends GetxController {
  InventoryDetailsController(this.repository);

  final InventoryRepository repository;

  final Rx<InventoryModel?> inventory = Rx<InventoryModel?>(null);
  final RxList<StockHistoryModel> history = <StockHistoryModel>[].obs;
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      inventory.value = await repository.getById(id);
      history.assignAll(await repository.history(id));
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> changeStatus(String newStatus, {String? reason}) async {
    final InventoryModel? current = inventory.value;
    if (current?.id == null) return false;
    try {
      await repository.adjust(
        inventoryId: current!.id!,
        newStatus: newStatus,
        reason: reason,
      );
      await load(current.id!);
      return true;
    } catch (_) {
      return false;
    }
  }
}
