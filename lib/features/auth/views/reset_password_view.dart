import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Chooses a new password after following the reset link from the email.
class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final AuthController _auth = Get.find<AuthController>();
  final AuthService _authService = Get.find<AuthService>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final RxBool _saving = false.obs;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Choose a password of at least 8 characters.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: _auth.passwordController,
                    label: 'New password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: true,
                    validator: _auth.validatePassword,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _auth.confirmController,
                    label: 'Confirm new password',
                    prefixIcon: Icons.lock_reset_outlined,
                    obscureText: true,
                    validator: _validateConfirm,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Obx(
                    () => AppButton(
                      label: 'Update password',
                      icon: Icons.save_outlined,
                      expanded: true,
                      isLoading: _saving.value,
                      onPressed: _saving.value ? null : _submit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm the password.';
    if (value != _auth.passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _saving.value = true;
    try {
      await _authService.updatePassword(_auth.passwordController.text);
      if (!mounted) return;
      AppSnackbar.success(context, 'Password updated. Please sign in.');
      Get.offAllNamed(AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Could not update the password.');
    } finally {
      _saving.value = false;
    }
  }
}
