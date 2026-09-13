import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/features/search/models/search_result_model.dart';
import 'package:enterprise_bike_showroom/features/search/repositories/search_repository.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Debounced global search across the business entities.
class SearchController extends GetxController {
  SearchController(this.repository);

  final SearchRepository repository;

  final RxList<SearchResultModel> results = <SearchResultModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString query = ''.obs;

  Worker? _worker;

  @override
  void onInit() {
    super.onInit();
    _worker = ever<String>(
      query,
      (String value) => _search(value),
    );
  }

  /// Opens the search flow with an initial query (from the top bar).
  void openWith(String initial) {
    query.value = initial;
  }

  Future<void> _search(String term) async {
    final String t = term.trim();
    if (t.length < 2) {
      results.clear();
      return;
    }
    isLoading.value = true;
    try {
      final List<SearchResultModel> found = await repository.search(t);
      results.assignAll(found);
    } catch (e) {
      AppLogger.warning('SEARCH', 'search failed', error: e);
      results.clear();
    } finally {
      isLoading.value = false;
    }
  }

  /// Navigates to the tapped result.
  void open(SearchResultModel result) {
    if (result.route != null && result.route!.isNotEmpty) {
      Get.toNamed(result.route!);
      return;
    }
    switch (result.entityType) {
      case 'customer':
        Get.toNamed('${AppRoutes.customerDetails}/${result.id}');
      case 'customer_vehicle':
      case 'vehicle':
        Get.toNamed('${AppRoutes.vehicleDetails}/${result.id}');
      case 'inventory':
        Get.toNamed('${AppRoutes.inventoryDetails}/${result.id}');
      case 'product':
        Get.toNamed('${AppRoutes.productDetails}/${result.id}');
      case 'sale':
        Get.toNamed('${AppRoutes.saleDetails}/${result.id}');
      case 'invoice':
        Get.toNamed('${AppRoutes.invoiceDetails}/${result.id}');
      case 'payment':
        Get.toNamed('${AppRoutes.paymentDetails}/${result.id}');
      case 'loan':
        Get.toNamed('${AppRoutes.loanDetails}/${result.id}');
      case 'service':
        Get.toNamed('${AppRoutes.serviceDetails}/${result.id}');
      default:
        break;
    }
  }

  @override
  void onClose() {
    _worker?.dispose();
    super.onClose();
  }
}
