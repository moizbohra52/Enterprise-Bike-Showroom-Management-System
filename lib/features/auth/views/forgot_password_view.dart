import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_dialog.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Sends the Supabase password-reset email.
class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  AuthController get _auth => Get.find<AuthController>();

  Future<void> _submit() async {
    final FormState? form = _formKey.currentState;
    if (form != null && !form.validate()) return;
    FocusScope.of(context).unfocus();
    final bool ok = await _auth.requestPasswordReset();
    if (!mounted) return;
    if (!ok) {
      AppSnackbar.error(context, _auth.errorMessage.value);
      return;
    }
    await AppDialog.show(
      context,
      title: 'Reset link sent',
      message: 'If that email belongs to an account, a password reset link is '
          'on its way. Open it and continue here.',
      icon: Icons.mark_email_read_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset your password')),
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
                        Icons.lock_reset_outlined,
                        size: 40,
                        color: context.colors.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Forgot password?',
                        textAlign: TextAlign.center,
                        style: context.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter your work email and we will send you a secure '
                        'reset link.',
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      AppTextField(
                        controller: _auth.emailController,
                        label: 'Email',
                        hint: 'manager@showroom.in',
                        prefixIcon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        validator: _auth.validateEmail,
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
                          label: 'Send reset link',
                          icon: Icons.send_outlined,
                          size: AppButtonSize.large,
                          expanded: true,
                          isLoading: _auth.isSubmitting.value,
                          onPressed: _submit,
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
