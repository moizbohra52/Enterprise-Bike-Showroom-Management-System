import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/config/theme_config.dart';
import 'package:enterprise_bike_showroom/features/auth/controllers/session_controller.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Entry screen: restores the persisted session, then routes.
///
/// - signed in with a profile -> dashboard
/// - signed in without a profile (onboarding pending) -> login with a hint
/// - signed out -> login
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  final SessionController _session = Get.find<SessionController>();

  Worker? _readyWorker;

  @override
  void initState() {
    super.initState();
    if (_session.isAuthReady.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _route());
    } else {
      _readyWorker = ever<bool>(_session.isAuthReady, (_) => _route());
    }
  }

  void _route() {
    if (!mounted) return;
    if (_session.isAuthenticated) {
      Get.offAllNamed(AppRoutes.dashboard);
    } else {
      Get.offAllNamed(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _readyWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.pedals, size: 52, color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              AppConfig.appName,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Multi-showroom bike retail, service & finance',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppLoader(message: 'Preparing your workspace…'),
          ],
        ),
      ),
    );
  }
}
