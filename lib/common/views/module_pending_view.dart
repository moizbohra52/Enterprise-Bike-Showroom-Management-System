import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:flutter/material.dart';

/// Placeholder for routes that are declared in [AppRoutes] but whose screen
/// has not been built yet, so navigation never dead-ends.
class ModulePendingView extends StatelessWidget {
  const ModulePendingView({super.key, required this.module});

  /// Human readable module name (used as page title + message).
  final String module;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: module,
      child: AppEmptyState(
        icon: Icons.construction_outlined,
        title: '$module is not available in this build',
        message: 'The route is registered, but the screen for this module has '
            'not been implemented yet. It will appear here without any '
            'navigation changes once it lands.',
      ),
    );
  }
}
