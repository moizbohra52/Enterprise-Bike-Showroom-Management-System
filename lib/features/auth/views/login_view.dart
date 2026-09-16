import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Email + password sign in.
///
/// Navigation after a successful sign-in is driven by the loaded profile: the
/// user must be linked to at least one showroom and one role before the
/// dashboard is reachable.
class LoginView extends GetView<AuthController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionController session = Get.find<SessionController>();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _brand(theme),
                const SizedBox(height: AppSpacing.xl),
                Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AppTextField(
                        controller: controller.emailController,
                        label: 'Work email',
                        hint: 'you@showroom.com',
                        prefixIcon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: controller.validateEmail,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Obx(
                        () => AppTextField(
                          controller: controller.passwordController,
                          label: 'Password',
                          prefixIcon: Icons.lock_outline,
                          obscureText: controller.obscurePassword.value,
                          textInputAction: TextInputAction.done,
                          validator: controller.validatePassword,
                          onSubmitted: (_) => _submit(context, session),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Get.toNamed(
                            AppRoutes.forgotPassword,
                          ),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Obx(
                        () => AppButton(
                          label: 'Sign in',
                          icon: Icons.login,
                          expanded: true,
                          size: AppButtonSize.large,
                          isLoading: controller.isSubmitting.value,
                          onPressed: controller.isSubmitting.value
                              ? null
                              : () => _submit(context, session),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Obx(
                        () => controller.errorMessage.value.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.sm,
                                ),
                                child: Text(
                                  controller.errorMessage.value,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                if (EnvironmentConfig.isPlaceholderBackend) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Backend is not configured: build with '
                    '--dart-define=SUPABASE_URL=... '
                    '--dart-define=SUPABASE_ANON_KEY=...',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(
                    '${AppConfig.appName} v${AppConfig.appVersion}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand(ThemeData theme) {
    return Column(
      children: <Widget>[
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.two_wheeler, size: 40, color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(AppConfig.appName, style: theme.textTheme.titleLarge),
        Text(
          'Sign in to continue',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context, SessionController session) async {
    controller.clearMessages();
    final bool signedIn = await controller.signIn();
    if (!signedIn) return;
    await session.loadProfile();
    if (!session.isAuthenticated) {
      AppSnackbar.warning(
        context,
        'Signed in, but no showroom profile is linked to this account yet. '
        'Ask an administrator to assign your showroom and role.',
      );
      return;
    }
    AppSnackbar.success(context, 'Welcome back, ${session.displayName}');
    Get.offAllNamed(AppRoutes.dashboard);
  }
}
