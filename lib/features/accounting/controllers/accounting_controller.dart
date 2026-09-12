import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/accounting/models/accounting_models.dart';
import 'package:enterprise_bike_showroom/features/accounting/repositories/accounting_repository.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';

/// Chart of accounts.
class AccountController extends BaseListController<AccountModel> {
  AccountController(this.repository)
      : super(repository.listAccounts, pageSize: 20);

  final AccountingRepository repository;

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }

  Future<List<Map<String, dynamic>>> ledger(AccountModel account) async {
    return repository.accountLedger(account.id!);
  }

  Future<AccountModel> saveAccount(Map<String, dynamic> payload,
      {String? id}) async {
    if (id != null) {
      throw AppException('Accounts are immutable after creation.');
    }
    return repository.createAccount(payload);
  }
}

/// Journal register.
class JournalController extends BaseListController<JournalEntryModel> {
  JournalController(AccountingRepository repository)
      : super(repository.listJournals, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }
}

/// Journal entry details.
class JournalDetailsController extends GetxController {
  JournalDetailsController(this.repository);

  final AccountingRepository repository;

  final Rx<JournalEntryModel?> entry = Rx<JournalEntryModel?>(null);
  final RxBool isLoading = true.obs;

  Future<void> load(String id) async {
    isLoading.value = true;
    try {
      entry.value = await repository.journalById(id);
    } finally {
      isLoading.value = false;
    }
  }
}

/// Manual journal entry builder.
class ManualEntryController extends GetxController {
  ManualEntryController(this.repository, this.session);

  final AccountingRepository repository;
  final SessionController session;

  final RxList<AccountModel> accounts = <AccountModel>[].obs;
  final RxList<JournalLineModel> lines = <JournalLineModel>[].obs;
  final Rx<DateTime?> entryDate = Rx<DateTime?>(null);
  final Rx<String> narration = ''.obs;

  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  Future<void> init() async {
    try {
      accounts.assignAll(await repository.allAccounts());
    } catch (e) {
      error.value = e.toString();
    }
  }

  num get totalDebit => lines.value
      .where((JournalLineModel l) => l.side == 'debit')
      .fold<num>(0, (num sum, JournalLineModel l) => sum + l.amount);

  num get totalCredit => lines.value
      .where((JournalLineModel l) => l.side == 'credit')
      .fold<num>(0, (num sum, JournalLineModel l) => sum + l.amount);

  bool get balanced => totalDebit == totalCredit && totalDebit > 0;

  void addLine() {
    lines.add(JournalLineModel(side: 'debit', amount: 0));
  }

  void updateLine(int index,
      {String? accountId, String? side, num? amount}) {
    if (index < 0 || index >= lines.value.length) return;
    final JournalLineModel old = lines.value[index];
    final String? newId = accountId ?? old.accountId;
    lines.value[index] = JournalLineModel(
      id: old.id,
      entryId: old.entryId,
      accountId: newId,
      accountName: _nameFor(newId) ?? old.accountName,
      accountCode: _codeFor(newId) ?? old.accountCode,
      side: side ?? old.side,
      amount: amount ?? old.amount,
      notes: old.notes,
    );
    lines.refresh();
  }

  void removeLine(int index) {
    if (index >= 0 && index < lines.value.length) {
      lines.removeAt(index);
    }
  }

  String? _nameFor(String? accountId) {
    for (final AccountModel a in accounts.value) {
      if (a.id == accountId) return a.name;
    }
    return null;
  }

  String? _codeFor(String? accountId) {
    for (final AccountModel a in accounts.value) {
      if (a.id == accountId) return a.code;
    }
    return null;
  }

  Future<bool> submit() async {
    error.value = '';
    final DateTime? date = entryDate.value;
    if (date == null) {
      error.value = 'Select the entry date.';
      return false;
    }
    if (narration.value.trim().length < 3) {
      error.value = 'Add a narration.';
      return false;
    }
    if (lines.value.length < 2) {
      error.value = 'An entry needs at least two lines.';
      return false;
    }
    if (!balanced) {
      error.value = 'Debits must equal credits.';
      return false;
    }
    if (session.activeShowroomId.isEmpty) {
      error.value = 'Select an active showroom first.';
      return false;
    }
    saving.value = true;
    try {
      await repository.createManualEntry(
        showroomId: session.activeShowroomId,
        entryDate: date,
        narration: narration.value.trim(),
        lines: lines.value,
      );
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      saving.value = false;
    }
  }
}
