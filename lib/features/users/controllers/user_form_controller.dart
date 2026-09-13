import 'package:enterprise_bike_showroom/common/models/role_model.dart';
import 'package:enterprise_bike_showroom/common/models/user_model.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/validators/validators.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/features/users/repositories/user_repository.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Create / edit form for application users.
///
/// Creating a user also creates the Supabase auth account (email + temporary
/// password) so the profile is usable immediately; role and showroom
/// assignment is what grants access afterwards.
class UserFormController extends GetxController {
  UserFormController(this.repository, this.session, this.authService);

  final UserRepository repository;
  final SessionController session;
  final AuthService authService;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final RxString userId = ''.obs;
  final RxBool isLoading = false.obs;
  final RxBool isSaving = false.obs;
  final RxString errorMessage = ''.obs;
  final RxList<RoleModel> availableRoles = <RoleModel>[].obs;
  final RxList<String> selectedRoleIds = <String>[].obs;
  final RxString selectedShowroomId = ''.obs;

  bool get isEdit => userId.value.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    final String? id = Get.parameters['id'];
    selectedShowroomId.value = session.activeShowroomId;
    load(id);
  }

  @override
  void onClose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  /// Loads roles always, and the user profile when editing.
  Future<void> load(String? id) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      availableRoles.assignAll(await repository.listRoles());
      if (id != null && id.isNotEmpty) {
        userId.value = id;
        final UserModel? user = await repository.getById(id);
        if (user != null) {
          nameController.text = user.name;
          emailController.text = user.email;
          phoneController.text = user.phone;
          selectedShowroomId.value = user.showroomId ?? '';
          selectedRoleIds.assignAll(await repository.roleIdsFor(id));
        } else {
          errorMessage.value = 'That user no longer exists.';
        }
      }
    } on AppException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      AppLogger.error('USERFORM', 'load failed', error: e);
    } finally {
      isLoading.value = false;
    }
  }

  void toggleRole(String roleId) {
    if (selectedRoleIds.contains(roleId)) {
      selectedRoleIds.remove(roleId);
    } else {
      selectedRoleIds.add(roleId);
    }
  }

  String? validateName(String? value) =>
      AppValidators.required(value, message: 'Name is required.');

  String? validateEmail(String? value) => AppValidators.email(value);

  String? validatePhone(String? value) => AppValidators.optionalPhone(value);

  String? validatePassword(String? value) {
    if (isEdit) return null;
    if (value == null || value.isEmpty) {
      return 'A temporary password is required.';
    }
    return AppValidators.minLength(value, 8);
  }

  /// Persists the profile + role assignment. Returns true on success.
  Future<bool> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return false;
    isSaving.value = true;
    errorMessage.value = '';
    try {
      if (isEdit) {
        await repository.update(
          userId.value,
          <String, dynamic>{
            'name': nameController.text.trim(),
            'email': emailController.text.trim().toLowerCase(),
            'phone': phoneController.text.trim(),
            if (selectedShowroomId.value.isNotEmpty)
              'showroom_id': selectedShowroomId.value,
          },
        );
        await repository.setRoles(userId.value, selectedRoleIds.toList());
      } else {
        final User authUser = await authService.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
          data: <String, String>{'name': nameController.text.trim()},
        );
        await repository.createProfile(
          authUserId: authUser.id,
          name: nameController.text.trim(),
          email: emailController.text.trim().toLowerCase(),
          phone: phoneController.text.trim(),
          showroomId:
              selectedShowroomId.value.isEmpty ? null : selectedShowroomId.value,
          roleIds: selectedRoleIds.toList(),
        );
      }
      return true;
    } on AppException catch (e) {
      errorMessage.value = e.message;
      return false;
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      AppLogger.error('USERFORM', 'save failed', error: e);
      return false;
    } finally {
      isSaving.value = false;
    }
  }
}
