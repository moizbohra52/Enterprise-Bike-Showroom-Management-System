import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/enums/finance_enums.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/extensions/num_extensions.dart';
import 'package:enterprise_bike_showroom/core/helpers/emi_calculator.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/sales/models/sale_models.dart';
import 'package:enterprise_bike_showroom/features/sales/repositories/sale_repository.dart';

/// Sale list controller.
class SaleController extends BaseListController<SaleModel> {
  SaleController(SaleRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }
}

/// The sale wizard: customer → vehicle → extras → payment → submit.
class SaleFormController extends GetxController {
  SaleFormController(this.repository, this.session);

  final SaleRepository repository;
  final SessionController session;

  // Customer
  final RxList<Map<String, dynamic>> customers = <Map<String, dynamic>>[].obs;
  final Rx<String?> customerId = Rx<String?>(null);
  final Rx<String> customerSearch = ''.obs;

  // Vehicle
  final RxList<Map<String, dynamic>> availableVehicles =
      <Map<String, dynamic>>[].obs;
  final Rx<String?> selectedVehicleId = Rx<String?>(null);

  // Accessories
  final RxList<Map<String, dynamic>> accessories = <Map<String, dynamic>>[].obs;
  final Map<String, int> accessoryQty = <String, int>{}.obs();

  // Money
  final Rx<num> vehiclePrice = 0.obs;
  final Rx<num> discount = 0.obs;
  final Rx<num> accessoriesTotal = 0.obs;
  final Rx<num> total = 0.obs;
  final Rx<num> taxAmount = 0.obs;
  num taxRate = 0;

  // EMI
  final RxList<Map<String, dynamic>> emiPlans = <Map<String, dynamic>>[].obs;
  final Rx<String?> emiPlanId = Rx<String?>(null);
  final Rx<num> downPayment = 0.obs;
  final Rx<num> monthlyEmi = 0.obs;
  final Rx<int> tenure = 12.obs;
  final Rx<num> loanAmount = 0.obs;
  final Rx<num> totalEmi = 0.obs;

  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  // Delivery (optional; can be completed at sale time or later)
  final RxBool deliveryEnabled = false.obs;
  final Rx<DateTime?> deliveryDate = Rx<DateTime?>(null);
  final Rx<String> odometer = ''.obs;
  final Rx<String> registration = ''.obs;

  /// Builds the delivery payload (null when delivery is not completed now).
  Map<String, dynamic>? buildDelivery() {
    final DateTime? date = deliveryDate.value;
    if (!deliveryEnabled.value || date == null) return null;
    return <String, dynamic>{
      'delivery_date': date.toIso8601String(),
      'odometer': double.tryParse(odometer.value) ?? 0,
      'registration_number': registration.value.trim(),
    };
  }

  /// Loads customers (and pre-selects when opened from Customer 360).
  Future<void> init({String? customerId}) async {
    taxRate = session.taxRate;
    ever(customerSearch, (String _) => _debouncedCustomerSearch());
    await loadCustomers();
    if (customerId != null && customerId.isNotEmpty) {
      await selectCustomer(customerId);
    }
  }

  Future<void> _debouncedCustomerSearch() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await loadCustomers();
  }

  Future<void> loadCustomers() async {
    final String? term = customerSearch.value.trim();
    try {
      customers.assignAll(
        await repository.searchCustomers(
          term,
          showroomId: session.activeShowroomId.isNotEmpty
              ? session.activeShowroomId
              : null,
        ),
      );
    } catch (e) {
      error.value = ErrorMapper.friendly(e);
    }
  }

  Future<void> selectCustomer(String id) async {
    customerId.value = id;
    // Vehicles available at the active showroom.
    final String showroomId = session.activeShowroomId;
    if (showroomId.isEmpty) {
      error.value = 'Select an active showroom first (top bar).';
      return;
    }
    final List<Map<String, dynamic>> rows =
        await repository.availableVehicles(showroomId);
    availableVehicles.assignAll(rows);
  }

  /// Selects a vehicle; loads its accessories + EMI plans.
  Future<void> selectVehicle(String id) async {
    selectedVehicleId.value = id;
    final Map<String, dynamic>? vehicle =
        availableVehicles.value.firstWhere((Map<String, dynamic> v) =>
            SafeJson.asId(v['id']) == id,
            orElse: () => <String, dynamic>{});
    if (vehicle.isEmpty) return;
    final dynamic product = vehicle['product'];
    final Map<String, dynamic> pm =
        product is Map ? SafeJson.asMap(product) : <String, dynamic>{};
    vehiclePrice.value = SafeJson.asMoney(pm['mrp_price']);
    final String? productId = SafeJson.asId(vehicle['product_id']);
    if (productId != null) {
      accessories.assignAll(await repository.accessoriesForProduct(productId));
      accessoryQty.clear();
      emiPlans.assignAll(await repository.emiPlans(productId));
      if (emiPlans.value.isNotEmpty) {
        emiPlanId.value = SafeJson.asId(emiPlans.value.first['id']);
      }
      _recalc();
    }
  }

  void setAccessoryQty(String accessoryId, int qty) {
    if (qty <= 0) {
      accessoryQty.remove(accessoryId);
    } else {
      accessoryQty[accessoryId] = qty;
    }
    _recalc();
  }

  void _recalc() {
    num acc = 0;
    for (final Map<String, dynamic> row in accessories.value) {
      final String? id = SafeJson.asId(row['id']);
      if (id == null) continue;
      final dynamic accProduct = row['accessory'];
      final num price = accProduct is Map
          ? SafeJson.asMoney(SafeJson.asMap(accProduct)['mrp_price'])
          : 0;
      acc += price * (accessoryQty[id] ?? 0);
    }
    accessoriesTotal.value = acc;
    final num subtotal = vehiclePrice.value + acc - discount.value;
    taxAmount.value = (subtotal * taxRate / 100).toIntAsMoney();
    total.value = subtotal + taxAmount.value;

    // EMI preview (server is authoritative at creation).
    final num loan = total.value - downPayment.value;
    loanAmount.value = loan > 0 ? loan : 0;
    if (loan > 0 && tenure.value > 0) {
      final Map<String, dynamic> plan = _selectedPlan();
      final num rate = SafeJson.asMoney(plan['interest_rate']);
      final InterestType method = SafeJson.asText(plan['method'],
              fallback: InterestType.reducing.value) ==
          InterestType.flat.value
          ? InterestType.flat
          : InterestType.reducing;
      monthlyEmi.value =
          EmiCalculator.monthlyEmi(loan, rate, tenure.value, method: method);
      totalEmi.value =
          EmiCalculator.totalEmi(loan, rate, tenure.value, method: method);
    } else {
      monthlyEmi.value = 0;
      totalEmi.value = 0;
    }
  }

  Map<String, dynamic> _selectedPlan() {
    for (final Map<String, dynamic> plan in emiPlans.value) {
      if (SafeJson.asId(plan['id']) == emiPlanId.value) return plan;
    }
    return <String, dynamic>{};
  }

  /// Builds the line list for the server payload.
  List<Map<String, dynamic>> buildLines() {
    final List<Map<String, dynamic>> lines = <Map<String, dynamic>>[];
    final String? vehicleId = selectedVehicleId.value;
    if (vehicleId != null) {
      final Map<String, dynamic> vehicle = availableVehicles.value.firstWhere(
          (Map<String, dynamic> v) => SafeJson.asId(v['id']) == vehicleId,
          orElse: () => <String, dynamic>{});
      final dynamic product = vehicle['product'];
      final Map<String, dynamic> pm = product is Map ? SafeJson.asMap(product) : <String, dynamic>{};
      lines.add(<String, dynamic>{
        'item_type': 'vehicle',
        'inventory_id': vehicleId,
        'product_id': SafeJson.asId(vehicle['product_id']),
        'name': pm['name']?.toString() ?? 'Vehicle',
        'qty': 1,
        'unit_price': vehiclePrice.value,
        'discount': discount.value,
      });
    }
    for (final Map<String, dynamic> row in accessories.value) {
      final String? id = SafeJson.asId(row['id']);
      if (id == null) continue;
      final int qty = accessoryQty[id] ?? 0;
      if (qty <= 0) continue;
      final dynamic accProduct = row['accessory'];
      final Map<String, dynamic> am =
          accProduct is Map ? SafeJson.asMap(accProduct) : <String, dynamic>{};
      final num price = SafeJson.asMoney(am['mrp_price']);
      lines.add(<String, dynamic>{
        'item_type': 'accessory',
        'product_id': SafeJson.asId(am['id']),
        'name': am['name']?.toString() ?? 'Accessory',
        'qty': qty,
        'unit_price': price,
        'discount': 0,
      });
    }
    return lines;
  }

  bool get isEmi => paymentMode.value == 'emi';

  final Rx<String> paymentMode = 'cash'.obs;

  void changePaymentMode(String mode) {
    paymentMode.value = mode;
    if (mode == 'emi') {
      final num suggested = (total.value * 0.1).roundToDouble();
      if (downPayment.value == 0 && total.value > 0) {
        downPayment.value = suggested;
      }
    }
    _recalc();
  }

  /// Submits the complete sale (sale → invoice → first payment).
  Future<bool> submit({String? invoiceNumber, Map<String, dynamic>? delivery}) async {
    error.value = '';
    final String? customerId = this.customerId.value;
    final String? vehicleId = selectedVehicleId.value;
    if (customerId == null || vehicleId == null) {
      error.value = 'Select a customer and a vehicle.';
      return false;
    }
    if (isEmi && downPayment.value <= 0) {
      error.value = 'Down payment is required for EMI sales.';
      return false;
    }
    saving.value = true;
    try {
      final Map<String, dynamic>? emi = isEmi
          ? <String, dynamic>{
              'plan_id': emiPlanId.value,
              'down_payment': downPayment.value,
              'tenure_months': tenure.value,
            }
          : null;
      await repository.completeSale(
        customerId: customerId,
        showroomId: session.activeShowroomId,
        lines: buildLines(),
        paymentMode: paymentMode.value,
        discount: discount.value,
        taxRate: taxRate,
        emi: emi,
        firstPayment: isEmi ? downPayment.value : total.value,
        invoiceNumber: invoiceNumber,
        delivery: delivery,
      );
      return true;
    } catch (e) {
      error.value = ErrorMapper.friendly(e);
      return false;
    } finally {
      saving.value = false;
    }
  }
}

/// Sale details (read-only + actions).
class SaleDetailsController extends GetxController {
  SaleDetailsController(this.repository);

  final SaleRepository repository;

  final Rx<SaleModel?> sale = Rx<SaleModel?>(null);
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      sale.value = await repository.getById(id);
    } finally {
      isLoading.value = false;
    }
  }
}
