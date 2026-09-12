import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/features/finance/models/loan_models.dart';
import 'package:enterprise_bike_showroom/features/finance/repositories/loan_repository.dart';

/// Loan register.
class LoanController extends BaseListController<LoanModel> {
  LoanController(LoanRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }
}

/// Loan 360: loan summary + EMI schedule + pay action.
class LoanDetailsController extends GetxController {
  LoanDetailsController(this.repository);

  final LoanRepository repository;

  final Rx<LoanModel?> loan = Rx<LoanModel?>(null);
  final RxList<EmiScheduleModel> schedule = <EmiScheduleModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool paying = false.obs;
  final Rx<String> error = ''.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      loan.value = await repository.getById(id);
      schedule.assignAll(await repository.schedule(id));
    } finally {
      isLoading.value = false;
    }
  }

  /// Pays the given installment (transactional RPC).
  Future<bool> payInstallment(
    EmiScheduleModel row, {
    required String paymentMode,
    String? referenceNumber,
  }) async {
    final LoanModel? current = loan.value;
    if (current?.id == null) return false;
    error.value = '';
    paying.value = true;
    try {
      final List<EmiScheduleModel> updated = await repository.payEmi(
        loanId: current!.id!,
        installmentNo: row.installmentNo,
        paymentMode: paymentMode,
        referenceNumber: referenceNumber,
      );
      if (updated.isNotEmpty) schedule.assignAll(updated);
      loan.value = await repository.getById(current.id!);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      paying.value = false;
    }
  }

  int get paidCount =>
      schedule.value.where((EmiScheduleModel r) => r.status == 'paid').length;

  int get overdueCount =>
      schedule.value.where((EmiScheduleModel r) => r.status == 'overdue').length;

  num get totalPaid => schedule.value
      .fold(0, (num sum, EmiScheduleModel r) => sum + r.paidAmount);
}
