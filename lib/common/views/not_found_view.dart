import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Fallback page for routes that are not registered in `AppPages`.
class NotFoundView extends StatelessWidget {
  const NotFoundView({super.key, this.route});

  /// The requested route (when available).
  final String? route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppCard(
              padding: 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.route_outlined,
                    size: 56,
                    color: context.colors.tertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Page not wired up yet',
                    style: context.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    route == null || route!.isEmpty
                        ? 'This screen has no route definition.'
                        : 'No page is registered for "$route".',
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Back to dashboard',
                    icon: Icons.space_dashboard_outlined,
                    onPressed: () => Get.offAllNamed(AppRoutes.dashboard),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
