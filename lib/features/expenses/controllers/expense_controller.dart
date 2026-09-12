import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/expenses/models/expense_models.dart';
import 'package:enterprise_bike_showroom/features/expenses/repositories/expense_repository.dart';

/// Expense register.
class ExpenseController extends BaseListController<ExpenseModel> {
  ExpenseController(ExpenseRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }
}

/// New expense form.
class ExpenseFormController extends GetxController {
  ExpenseFormController(this.repository, this.session);

  final ExpenseRepository repository;
  final SessionController session;

  final RxList<ExpenseCategoryModel> categories = <ExpenseCategoryModel>[].obs;
  final Rx<String?> categoryId = Rx<String?>(null);
  final Rx<DateTime?> date = Rx<DateTime?>(null);
  final Rx<String> description = ''.obs;
  final Rx<num> amount = 0.obs;
  final Rx<String> paymentMode = 'cash'.obs;
  final Rx<String> reference = ''.obs;
  final Rx<String> voucher = ''.obs;
  final Rx<String> notes = ''.obs;
  final Rx<String?> attachmentPath = Rx<String?>(null);

  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  Future<void> init() async {
    try {
      categories.assignAll(
        await repository.categories(
            showroomId: session.activeShowroomId.isNotEmpty
                ? session.activeShowroomId
                : null),
      );
    } on AppException catch (e) {
      error.value = e.message;
    }
  }

  bool get requiresApproval {
    for (final ExpenseCategoryModel c in categories.value) {
      if (c.id == categoryId.value) return c.requiresApproval;
    }
    return true;
  }

  Future<bool> submit() async {
    error.value = '';
    final String? category = categoryId.value;
    final DateTime? when = date.value;
    if (category == null) {
      error.value = 'Select a category.';
      return false;
    }
    if (when == null) {
      error.value = 'Select the expense date.';
      return false;
    }
    if (description.value.trim().length < 3) {
      error.value = 'Describe the expense.';
      return false;
    }
    if (amount.value <= 0) {
      error.value = 'Enter a positive amount.';
      return false;
    }
    if (session.activeShowroomId.isEmpty) {
      error.value = 'Select an active showroom first.';
      return false;
    }
    saving.value = true;
    try {
      await repository.create(
        categoryId: category,
        showroomId: session.activeShowroomId,
        description: description.value.trim(),
        amount: amount.value,
        date: when,
        paymentMode: paymentMode.value,
        referenceNumber:
            reference.value.trim().isEmpty ? null : reference.value.trim(),
        voucherNumber:
            voucher.value.trim().isEmpty ? null : voucher.value.trim(),
        attachmentPath: attachmentPath.value,
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

/// Expense details + approve / reject.
class ExpenseDetailsController extends GetxController {
  ExpenseDetailsController(this.repository, this.session);

  final ExpenseRepository repository;
  final SessionController session;

  final Rx<ExpenseModel?> expense = Rx<ExpenseModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool busy = false.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      expense.value = await repository.getById(id);
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> approve() async {
    final ExpenseModel? current = expense.value;
    if (current?.id == null || current?.status != 'pending') return false;
    busy.value = true;
    try {
      await repository.approve(current!.id!, session.user.value?.id ?? '');
      expense.value = await repository.getById(current.id!);
      return true;
    } on AppException {
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> reject(String reason) async {
    final ExpenseModel? current = expense.value;
    if (current?.id == null || current?.status != 'pending') return false;
    busy.value = true;
    try {
      await repository
          .reject(current!.id!, session.user.value?.id ?? '', reason);
      expense.value = await repository.getById(current.id!);
      return true;
    } on AppException {
      return false;
    } finally {
      busy.value = false;
    }
  }
}
