import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/environment_config.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_bootstrap.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:enterprise_bike_showroom/services/auth_service.dart';

/// Startup screen: waits for session restore, then routes to dashboard/login.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  bool _profilePending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    if (!AppBootstrap.isBackendReady) {
      // No backend: nothing to restore, straight to the (disabled) login.
      if (mounted) Get.offAllNamed(AppRoutes.login);
      return;
    }
    final SessionController session = Get.find<SessionController>();
    int ticks = 0;
    while (!session.isAuthReady.value && ticks < 200) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ticks++;
    }
    if (!mounted) return;

    if (session.isAuthenticated) {
      Get.offAllNamed(AppRoutes.dashboard);
      return;
    }
    // Authenticated with Supabase but without an application profile: the
    // account still has to be invited/linked by an administrator.
    if (Get.find<AuthService>().hasSession) {
      setState(() => _profilePending = true);
      return;
    }
    Get.offAllNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.two_wheeler_outlined,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  AppConfig.appName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Multi-showroom sales, inventory, service & finance',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                if (_profilePending)
                  _profilePendingCard(context)
                else
                  const Column(
                    children: <Widget>[
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      SizedBox(height: 14),
                      Text('Restoring your session…'),
                    ],
                  ),
                if (!AppBootstrap.isBackendReady) ...<Widget>[
                  const SizedBox(height: 24),
                  _offlineCard(context),
                ],
                const SizedBox(height: 28),
                Text(
                  'v${AppConfig.appVersion}+${AppConfig.appBuildNumber} · '
                  '${EnvironmentConfig.environmentLabel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profilePendingCard(BuildContext context) {
    return AppCard(
      padding: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.person_off_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          const SizedBox(height: 10),
          Text(
            'Account not linked yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Your login is valid, but no showroom profile exists for it. An '
            'administrator must create your user profile (Users > Add User) '
            'before you can sign in.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Back to sign in',
            variant: AppButtonVariant.outlined,
            onPressed: () => Get.offAllNamed(AppRoutes.login),
          ),
        ],
      ),
    );
  }

  Widget _offlineCard(BuildContext context) {
    return AppCard(
      padding: 16,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: <Widget>[
          Icon(
            Icons.cloud_off_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Backend not configured. Build with --dart-define=SUPABASE_URL='
              '… --dart-define=SUPABASE_ANON_KEY=… to enable sign-in and sync.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
