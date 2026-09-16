import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';
import 'package:enterprise_bike_showroom/common/models/showroom_model.dart';
import 'package:enterprise_bike_showroom/features/products/models/product_models.dart';
import 'package:enterprise_bike_showroom/features/products/repositories/product_repository.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Product list + brand filter.
class ProductController extends BaseListController<ProductModel> {
  ProductController(ProductRepository repository)
      : super(repository.list, pageSize: 20) {
    this.repository = repository;
  }

  late final ProductRepository repository;

  final RxList<BrandModel> brands = <BrandModel>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    await loadBrands();
    refresh();
  }

  Future<void> loadBrands() async {
    try {
      brands.assignAll(await repository.listBrands());
    } catch (_) {
      brands.clear();
    }
  }

  List<DropdownOption<String?>> get brandOptions {
    return <DropdownOption<String?>>[
      const DropdownOption<String?>(value: null, label: 'All brands'),
      for (final BrandModel b in brands)
        DropdownOption<String?>(value: b.id, label: b.name),
    ];
  }

  void applyBrandFilter(String? brandId) {
    if (brandId == null) {
      setFilter('brand_id', null);
    } else {
      setFilter('brand_id', brandId);
    }
  }

  Future<void> openForm({String? id}) async {
    await Get.toNamed(
      AppRoutes.productForm,
      parameters: <String, String>{
        if (id != null) 'id': id,
      },
    );
    refresh();
  }

  Future<void> openDetails(ProductModel product) async {
    await Get.toNamed(AppRoutes.productDetails,
        parameters: <String, String>{'id': product.id!});
  }
}

/// Product details (profile, colors, images, specs).
class ProductDetailsController extends GetxController {
  ProductDetailsController(this.repository);

  final ProductRepository repository;

  final Rx<ProductModel?> product = Rx<ProductModel?>(null);
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      product.value = await repository.getById(id);
    } finally {
      isLoading.value = false;
    }
  }

  /// Deletes (soft) the current product.
  Future<bool> delete() async {
    final ProductModel? current = product.value;
    if (current?.id == null) return false;
    try {
      await repository.softDelete(current!.id!);
      product.value = null;
      return true;
    } catch (_) {
      return false;
    }
  }
}
