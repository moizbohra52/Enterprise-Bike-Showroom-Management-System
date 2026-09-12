import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/config/theme_config.dart';

/// Inline loading indicator (page body sized).
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.message, this.small = false});

  final String? message;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: small ? 22 : 36,
            height: small ? 22 : 36,
            child: CircularProgressIndicator(
              strokeWidth: small ? 2 : 3,
              color: theme.colorScheme.primary,
            ),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(message!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Full-screen overlay loader (wraps a page while an operation runs).
class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({super.key, this.show = true, this.message});

  final bool show;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Container(
      color: Colors.black26,
      child: AppLoader(message: message ?? 'Please wait…'),
    );
  }
}
