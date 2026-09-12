import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';

/// Pagination bar: page controls + page-size selector.
class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.info,
    required this.onPageChanged,
    this.onPageSizeChanged,
  });

  final PageInfo info;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          '${info.total} record${info.total == 1 ? '' : 's'} · '
          'page ${info.page} of ${info.totalPages}',
          style: theme.textTheme.bodySmall,
        ),
        Row(
          children: <Widget>[
            if (onPageSizeChanged != null)
              DropdownButton<int>(
                value: info.pageSize,
                underline: const SizedBox.shrink(),
                items: <DropdownMenuItem<int>>[
                  for (final int size in AppConfig.pageSizeOptions)
                    DropdownMenuItem<int>(
                      value: size,
                      child: Text('$size / page'),
                    ),
                ],
                onChanged: (int? value) {
                  if (value != null) onPageSizeChanged?.call(value);
                },
              ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous page',
              onPressed: info.page > 1 ? () => onPageChanged(info.page - 1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next page',
              onPressed: info.page < info.totalPages
                  ? () => onPageChanged(info.page + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
