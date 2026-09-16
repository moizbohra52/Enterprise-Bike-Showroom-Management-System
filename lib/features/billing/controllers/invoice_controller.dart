import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/billing/models/invoice_models.dart';
import 'package:enterprise_bike_showroom/features/billing/repositories/invoice_repository.dart';

/// Invoice list controller.
class InvoiceController extends BaseListController<InvoiceModel> {
  InvoiceController(InvoiceRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    super.onInit();
    refresh();
  }
}

/// Invoice details: document + payments + actions (pay / void / pdf).
class InvoiceDetailsController extends GetxController {
  InvoiceDetailsController(this.repository);

  final InvoiceRepository repository;

  final Rx<InvoiceModel?> invoice = Rx<InvoiceModel?>(null);
  final RxList<Map<String, dynamic>> payments = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      invoice.value = await repository.getById(id);
      payments.assignAll(await repository.paymentsFor(id));
    } finally {
      isLoading.value = false;
    }
  }

  /// Receives a payment against this invoice.
  Future<bool> pay({
    required num amount,
    required String paymentMode,
    String? referenceNumber,
    String? notes,
  }) async {
    final InvoiceModel? current = invoice.value;
    if (current?.id == null) return false;
    try {
      await repository.recordPayment(
        invoiceId: current!.id!,
        amount: amount,
        paymentMode: paymentMode,
        customerId: current.customerId,
        referenceNumber: referenceNumber,
        notes: notes,
      );
      await load(current.id!);
      return true;
    } on AppException {
      return false;
    }
  }

  /// Voids the invoice (no payments recorded).
  Future<bool> voidInvoice(String reason) async {
    final InvoiceModel? current = invoice.value;
    if (current?.id == null) return false;
    try {
      await repository.voidInvoice(current!.id!, reason);
      invoice.value = current.copyWith(status: 'void', voidReason: reason);
      return true;
    } on AppException {
      return false;
    }
  }
}

extension InvoiceModelCopy on InvoiceModel {
  InvoiceModel copyWith({String? status, String? voidReason}) {
    return InvoiceModel(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      showroomId: showroomId,
      customerId: customerId,
      customer: customer,
      saleId: saleId,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      dueDate: dueDate,
      status: status ?? this.status,
      paymentMode: paymentMode,
      subtotal: subtotal,
      discountAmount: discountAmount,
      taxRate: taxRate,
      taxAmount: taxAmount,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      outstandingAmount: outstandingAmount,
      lineItems: lineItems,
      voidReason: voidReason ?? this.voidReason,
      voidedAt: voidedAt,
      notes: notes,
    );
  }
}
