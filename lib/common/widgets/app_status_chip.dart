import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/core/helpers/status_colors.dart';

/// Colored status pill used in tables, cards and details pages.
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.status,
    this.label,
    this.showIcon = true,
  });

  /// Wire status string (e.g. `in_progress`).
  final String status;

  /// Optional override label (defaults to humanized [status]).
  final String? label;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final Color color = StatusColors.color(status);
    final Color background = color.withAlpha(28);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showIcon)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(StatusColors.icon(status), size: 13, color: color),
            ),
          Text(
            label ?? AppFormatters.humanize(status),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
