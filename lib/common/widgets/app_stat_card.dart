import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/core/helpers/status_colors.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';

/// Dashboard KPI card.
class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    this.color,
    this.caption,
    this.trend,
    this.onTap,
    this.loading = false,
  });

  final String title;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? caption;

  /// Optional trend text (e.g. `+12% vs last month`).
  final String? trend;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = color ?? theme.colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? const AppLoader(small: true)
                    : Icon(icon ?? Icons.insights_outlined,
                        color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      loading ? '…' : AppFormatters.humanize(value),
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontSize: 22),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (caption != null || trend != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          if (trend != null)
                            Text(trend!,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: StatusColors.color('completed'))),
                          if (trend != null && caption != null)
                            const SizedBox(width: 6),
                          if (caption != null)
                            Flexible(
                              child: Text(caption!,
                                  style: theme.textTheme.labelSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
