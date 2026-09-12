import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_snackbar.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_text_field.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/auth_controller.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_bootstrap.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Email + password sign-in. On success the session drives navigation.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  AuthController get _auth => Get.find<AuthController>();

  @override
  void initState() {
    super.initState();
    _auth.clearMessages();
  }

  Future<void> _submit() async {
    final FormState? form = _formKey.currentState;
    if (form != null && !form.validate()) return;
    FocusScope.of(context).unfocus();
    final bool ok = await _auth.signIn();
    if (!mounted) return;
    if (!ok) {
      AppSnackbar.error(context, _auth.errorMessage.value);
      return;
    }
    await _routeAfterSignIn();
  }

  /// The profile load is triggered by the auth stream; give it a moment.
  Future<void> _routeAfterSignIn() async {
    final SessionController session = Get.find<SessionController>();
    int ticks = 0;
    while (!session.isAuthenticated && ticks < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ticks++;
    }
    if (!mounted) return;
    if (!session.isAuthenticated) {
      AppSnackbar.warning(
        context,
        'Signed in, but your user profile is not linked to a showroom yet.',
      );
      return;
    }
    Get.offAllNamed(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 940),
              child: context.isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        const Expanded(child: _BrandPanel()),
                        const SizedBox(width: 48),
                        Expanded(child: _form(context)),
                      ],
                    )
                  : Column(
                      children: <Widget>[
                        const _BrandCompact(),
                        const SizedBox(height: 32),
                        _form(context),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: AppCard(
        padding: 28,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Sign in',
                style: context.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Use your showroom account to continue.',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              AppTextField(
                controller: _auth.emailController,
                label: 'Email',
                hint: 'manager@showroom.in',
                prefixIcon: Icons.alternate_email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: _auth.validateEmail,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _auth.passwordController,
                label: 'Password',
                hint: 'At least 8 characters',
                prefixIcon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.done,
                validator: _auth.validatePassword,
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Get.toNamed(AppRoutes.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ),
              Obx(() {
                final String error = _auth.errorMessage.value;
                if (error.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error,
                    style: TextStyle(color: context.colors.error, fontSize: 13),
                  ),
                );
              }),
              Obx(
                () => AppButton(
                  label: 'Sign in',
                  icon: Icons.login,
                  size: AppButtonSize.large,
                  isLoading: _auth.isSubmitting.value,
                  expanded: true,
                  onPressed: _submit,
                ),
              ),
              if (!AppBootstrap.isBackendReady) ...<Widget>[
                const SizedBox(height: 20),
                _backendWarning(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _backendWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.errorContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.cloud_off_outlined, size: 18, color: context.colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No backend configured for this ${EnvironmentConfig.environmentLabel} '
              'build - sign-in is unavailable.',
              style: context.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop side panel (product summary).
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.two_wheeler_outlined, size: 44, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          AppConfig.appName,
          style: context.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'One system for the whole showroom floor: bookings, stock, invoicing, '
          'EMI follow-up, service job cards, warranty claims and daily accounts.',
          style: context.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        for (final String line in _highlights)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.check_circle_outline, size: 18, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(line, style: context.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }

  static const List<String> _highlights = <String>[
    'Multi-showroom stock with transfers and reservations',
    'Sales, GST invoices, receipts and EMI schedules',
    'Job cards, free-service plans and warranty claims',
    'Double-entry accounts with expense approvals',
    'Offline queue that syncs when the network returns',
  ];
}

/// Compact brand block (mobile / tablet).
class _BrandCompact extends StatelessWidget {
  const _BrandCompact();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(
          Icons.two_wheeler_outlined,
          size: 40,
          color: context.colors.primary,
        ),
        const SizedBox(height: 12),
        Text(
          AppConfig.appName,
          textAlign: TextAlign.center,
          style: context.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
