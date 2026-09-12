import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/config/theme_config.dart';

/// Standard surface card with optional title + actions.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.actions,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.margin,
    this.color,
  });

  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget child;
  final double padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: margin ?? const EdgeInsets.all(AppSpacing.sm),
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null || (actions?.isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title ?? '',
                              style: theme.textTheme.titleMedium,
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      if (actions != null)
                        ...actions!.map((Widget w) => Padding(
                              padding: const EdgeInsets.only(left: AppSpacing.xs),
                              child: w,
                            )),
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
