import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/features/products/controllers/product_controller.dart';
import 'package:enterprise_bike_showroom/features/products/repositories/product_repository.dart';

/// Registers product module dependencies.
class ProductBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProductRepository>(
      () => ProductRepository(Get.find()),
      fenix: true,
    );
    Get.lazyPut<ProductController>(
      () => ProductController(Get.find<ProductRepository>()),
      fenix: true,
    );
    Get.lazyPut<ProductDetailsController>(
      () => ProductDetailsController(Get.find<ProductRepository>()),
      fenix: true,
    );
  }
}
