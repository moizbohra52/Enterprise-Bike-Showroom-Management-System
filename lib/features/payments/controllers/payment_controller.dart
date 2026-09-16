import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/payments/models/payment_models.dart';
import 'package:enterprise_bike_showroom/features/payments/repositories/payment_repository.dart';

/// Payment register.
class PaymentController extends BaseListController<PaymentModel> {
  PaymentController(PaymentRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    super.onInit();
    refresh();
  }
}

/// Record a payment against an invoice.
class PaymentFormController extends GetxController {
  PaymentFormController(this.repository, this.session);

  final PaymentRepository repository;
  final SessionController session;

  final Rx<String> invoiceId = ''.obs;
  final Rx<String> invoiceNumber = ''.obs;
  final Rx<num> outstanding = 0.obs;
  final Rx<num> amount = 0.obs;
  final Rx<String> mode = 'cash'.obs;
  final Rx<String> reference = ''.obs;
  final Rx<String> notes = ''.obs;
  final Rx<String> customerName = ''.obs;
  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  /// Loads the invoice context (by invoiceId, or resolves it from saleId).
  Future<void> init({String? invoiceId, String? saleId}) async {
    error.value = '';
    if (invoiceId != null && invoiceId.isNotEmpty) {
      await _loadByInvoice(invoiceId);
    } else if (saleId != null && saleId.isNotEmpty) {
      await _loadBySale(saleId);
    }
  }

  Future<void> _loadByInvoice(String id) async {
    try {
      invoiceId.value = id;
      outstanding.value = await repository.outstandingForInvoice(id);
    } on AppException catch (e) {
      error.value = e.message;
    }
  }

  Future<void> _loadBySale(String saleId) async {
    try {
      final String? invoice = await repository.invoiceIdForSale(saleId);
      if (invoice != null) {
        await _loadByInvoice(invoice);
      } else {
        error.value = 'This sale has no invoice yet.';
      }
    } on AppException catch (e) {
      error.value = e.message;
    }
  }

  Future<bool> submit() async {
    error.value = '';
    final String id = invoiceId.value;
    final num amt = amount.value;
    if (id.isEmpty) {
      error.value = 'No invoice selected.';
      return false;
    }
    if (amt <= 0) {
      error.value = 'Enter a payment amount.';
      return false;
    }
    if (amt > outstanding.value) {
      error.value = 'Amount exceeds outstanding (${outstanding.value}).';
      return false;
    }
    saving.value = true;
    try {
      await repository.recordPayment(
        invoiceId: id,
        amount: amt,
        paymentMode: mode.value,
        referenceNumber: reference.value.trim().isEmpty
            ? null
            : reference.value.trim(),
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

/// Payment details + refund action.
class PaymentDetailsController extends GetxController {
  PaymentDetailsController(this.repository);

  final PaymentRepository repository;

  final Rx<PaymentModel?> payment = Rx<PaymentModel?>(null);
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      payment.value = await repository.getById(id);
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> refund(String reason) async {
    final PaymentModel? current = payment.value;
    if (current?.id == null || (current?.refunded ?? false)) return false;
    try {
      await repository.refund(current!.id!, reason);
      payment.value = null;
      await load(current.id!);
      return true;
    } on AppException {
      return false;
    }
  }
}
