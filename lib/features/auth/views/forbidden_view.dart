import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/routes/app_routes.dart';

/// Shown when the signed-in user lacks the permission required by a page.
class ForbiddenView extends StatelessWidget {
  const ForbiddenView({super.key, this.permission, this.inline = false});

  /// The `module.action` permission that was missing (when known).
  final String? permission;

  /// Rendered inside [RouteGuard] (no scaffold chrome).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final Widget body = AppCard(
      padding: 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.no_encryption_outlined,
            size: 56,
            color: context.colors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Access restricted',
            style: context.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            permission == null
                ? 'Your role does not allow you to open this screen.'
                : 'Your role does not include the permission '
                    '"$permission". Ask an administrator to grant it in '
                    'Roles & Permissions.',
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: <Widget>[
              AppButton(
                label: 'Back to dashboard',
                icon: Icons.space_dashboard_outlined,
                onPressed: () => Get.offAllNamed(AppRoutes.dashboard),
              ),
              AppButton(
                label: 'Go back',
                variant: AppButtonVariant.outlined,
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Get.back();
                  } else {
                    Get.offAllNamed(AppRoutes.dashboard);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );

    final Widget content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: body,
        ),
      ),
    );

    if (inline) return content;
    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: content,
    );
  }
}
