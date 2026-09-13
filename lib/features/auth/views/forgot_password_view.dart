import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Requests a password reset email.
class ForgotPasswordView extends GetView<AuthController> {
  const ForgotPasswordView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Enter the email address of your account and we will send '
                    'you a link to choose a new password.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: controller.emailController,
                    label: 'Work email',
                    prefixIcon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: controller.validateEmail,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Obx(
                    () => AppButton(
                      label: 'Send reset link',
                      icon: Icons.send_outlined,
                      expanded: true,
                      isLoading: controller.isSubmitting.value,
                      onPressed: controller.isSubmitting.value
                          ? null
                          : () => _send(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Obx(
                    () => Text(
                      controller.errorMessage.value.isNotEmpty
                          ? controller.errorMessage.value
                          : controller.successMessage.value,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: controller.errorMessage.value.isNotEmpty
                            ? AppColors.error
                            : AppColors.success,
                      ),
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

  Future<void> _send(BuildContext context) async {
    controller.clearMessages();
    final bool sent = await controller.requestPasswordReset();
    if (sent) AppSnackbar.success(context, controller.successMessage.value);
  }
}
