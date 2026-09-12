import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/validators/validators.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';

/// Login / sign-up / password reset form controller.
class AuthController extends GetxController {
  AuthController(this.authService);

  final AuthService authService;

  final RxBool isLoading = false.obs;
  final RxBool isSubmitting = false.obs;
  final RxString errorMessage = ''.obs;
  final RxString successMessage = ''.obs;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();
  final RxBool obscurePassword = true.obs;

  /// Email validation for the current field value.
  String? validateEmail(String? value) => AppValidators.email(value);

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    return AppValidators.minLength(value, 8);
  }

  /// Signs in. On success the session stream drives navigation (splash ->
  /// dashboard); this method only reports failures.
  Future<bool> signIn() async {
    errorMessage.value = '';
    final String email = emailController.text.trim();
    final String password = passwordController.text;
    final String? emailError = AppValidators.email(email);
    if (emailError != null) {
      errorMessage.value = emailError;
      return false;
    }
    if (password.isEmpty) {
      errorMessage.value = 'Password is required.';
      return false;
    }
    isSubmitting.value = true;
    try {
      await authService.signIn(email: email, password: password);
      return true;
    } on AppException catch (e) {
      errorMessage.value = e.message;
      return false;
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  /// Signs up a new account. Profile completion (showroom/role) happens in
  /// the controlled onboarding workflow, not here.
  Future<bool> signUp() async {
    errorMessage.value = '';
    final String email = emailController.text.trim();
    final String password = passwordController.text;
    final String? emailError = AppValidators.email(email);
    if (emailError != null) {
      errorMessage.value = emailError;
      return false;
    }
    final String? passError = validatePassword(password);
    if (passError != null) {
      errorMessage.value = passError;
      return false;
    }
    isSubmitting.value = true;
    try {
      await authService.signUp(email: email, password: password);
      successMessage.value =
          'Account created. Check your inbox for the confirmation email.';
      return true;
    } on AppException catch (e) {
      errorMessage.value = e.message;
      return false;
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  /// Sends the password reset email.
  Future<bool> requestPasswordReset() async {
    errorMessage.value = '';
    final String email = emailController.text.trim();
    final String? emailError = AppValidators.email(email);
    if (emailError != null) {
      errorMessage.value = emailError;
      return false;
    }
    isSubmitting.value = true;
    try {
      await authService.sendPasswordReset(email);
      successMessage.value =
          'If the email exists, a reset link is on its way.';
      return true;
    } on AppException catch (e) {
      errorMessage.value = e.message;
      return false;
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  /// Completes a password reset (entered from the Supabase reset link).
  Future<bool> resetPassword() async {
    errorMessage.value = '';
    final String password = passwordController.text;
    final String confirm = confirmController.text;
    final String? passError = validatePassword(password);
    if (passError != null) {
      errorMessage.value = passError;
      return false;
    }
    if (password != confirm) {
      errorMessage.value = 'Passwords do not match.';
      return false;
    }
    isSubmitting.value = true;
    try {
      await authService.updatePassword(password);
      successMessage.value = 'Password updated. You can sign in now.';
      return true;
    } on AppException catch (e) {
      errorMessage.value = e.message;
      return false;
    } catch (e) {
      errorMessage.value = ErrorMapper.friendly(e);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  /// Signs out and returns to the login screen.
  Future<void> signOut() async {
    isLoading.value = true;
    try {
      await authService.signOut();
      AppLogger.info('AUTH', 'sign out requested');
      Get.offAllNamed(AppRoutes.login);
    } finally {
      isLoading.value = false;
    }
  }

  void toggleObscure() => obscurePassword.value = !obscurePassword.value;

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.onClose();
  }

  void clearMessages() {
    errorMessage.value = '';
    successMessage.value = '';
  }
}
