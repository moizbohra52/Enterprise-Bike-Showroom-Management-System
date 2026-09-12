import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_bootstrap.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';

/// Completes the password reset (opened from the Supabase reset link).
class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  AuthController get _auth => Get.find<AuthController>();

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your new password.';
    if (value != _auth.passwordController.text) return 'Passwords do not match.';
    return null;
  }

  Future<void> _submit() async {
    final FormState? form = _formKey.currentState;
    if (form != null && !form.validate()) return;
    FocusScope.of(context).unfocus();
    final bool ok = await _auth.resetPassword();
    if (!mounted) return;
    if (!ok) {
      AppSnackbar.error(context, _auth.errorMessage.value);
      return;
    }
    Get.offAllNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    // Reading the Supabase session requires an initialized client.
    final bool recoverySession = AppBootstrap.isBackendReady &&
        Get.find<AuthService>().hasSession;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a new password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppCard(
                padding: 28,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        Icons.password_rounded,
                        size: 40,
                        color: context.colors.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'New password',
                        textAlign: TextAlign.center,
                        style: context.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'At least 8 characters. Use letters, numbers and one '
                        'symbol.',
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (!recoverySession) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: context.colors.primary,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Open the reset link from your email on this '
                                  'device - it signs you in for the password '
                                  'change only.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      AppTextField(
                        controller: _auth.passwordController,
                        label: 'New password',
                        obscureText: true,
                        prefixIcon: Icons.lock_outline,
                        textInputAction: TextInputAction.next,
                        validator: _auth.validatePassword,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _auth.confirmController,
                        label: 'Confirm password',
                        obscureText: true,
                        prefixIcon: Icons.lock_person_outlined,
                        textInputAction: TextInputAction.done,
                        validator: _validateConfirm,
                        onSubmitted: (_) => _submit(),
                      ),
                      Obx(() {
                        final String error = _auth.errorMessage.value;
                        if (error.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error,
                            style: TextStyle(
                              color: context.colors.error,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 20),
                      Obx(
                        () => AppButton(
                          label: 'Update password',
                          icon: Icons.save_outlined,
                          size: AppButtonSize.large,
                          expanded: true,
                          isLoading: _auth.isSubmitting.value,
                          onPressed: recoverySession ? _submit : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Get.offAllNamed(AppRoutes.login),
                        child: const Text('Back to sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
