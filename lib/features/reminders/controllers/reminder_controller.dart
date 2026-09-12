import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/controllers/base_list_controller.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/reminders/models/reminder_models.dart';
import 'package:enterprise_bike_showroom/features/reminders/repositories/reminder_repository.dart';

/// Reminder center.
class ReminderController extends BaseListController<ReminderModel> {
  ReminderController(ReminderRepository repository)
      : super(repository.list, pageSize: 20);

  @override
  Future<void> onInit() async {
    await super.onInit();
    refresh();
  }

  Future<bool> markDone(ReminderModel reminder) async {
    try {
      await repository.setStatus(reminder.id!, 'done');
      return true;
    } on AppException {
      return false;
    }
  }

  Future<bool> dismiss(ReminderModel reminder) async {
    try {
      await repository.setStatus(reminder.id!, 'dismissed');
      return true;
    } on AppException {
      return false;
    }
  }
}

/// New reminder form.
class ReminderFormController extends GetxController {
  ReminderFormController(this.repository, this.session);

  final ReminderRepository repository;
  final SessionController session;

  final Rx<String> title = ''.obs;
  final Rx<String> message = ''.obs;
  final Rx<DateTime?> date = Rx<DateTime?>(null);
  final Rx<String> type = 'custom'.obs;
  final Rx<String?> customerId = Rx<String?>(null);

  final RxBool saving = false.obs;
  final Rx<String> error = ''.obs;

  Future<bool> submit() async {
    error.value = '';
    if (title.value.trim().length < 3) {
      error.value = 'Enter a title.';
      return false;
    }
    if (date.value == null) {
      error.value = 'Pick the reminder date.';
      return false;
    }
    saving.value = true;
    try {
      await repository.create(<String, dynamic>{
        'showroom_id':
            session.activeShowroomId.isEmpty ? null : session.activeShowroomId,
        'customer_id': customerId.value,
        'title': title.value.trim(),
        'message': message.value.trim(),
        'reminder_date':
            date.value!.toIso8601String().substring(0, 10),
        'type': type.value,
      });
      return true;
    } on AppException catch (e) {
      error.value = e.message;
      return false;
    } finally {
      saving.value = false;
    }
  }
}
