import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_error_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_pagination.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';

/// Column definition for [AppTable].
class AppColumn<T> {
  const AppColumn({
    required this.label,
    required this.value,
    this.numeric = false,
    this.expand = false,
    this.visible = true,
    this.tooltip,
  });

  final String label;
  final Widget Function(T item) value;

  /// Right-align + monospace-ish treatment for numbers/money.
  final bool numeric;
  final bool expand;
  final bool visible;

  /// Column visibility hint for the visibility menu.
  final String? tooltip;
}

/// A responsive data grid.
///
/// Desktop: real [DataTable] with sorting.
/// Mobile: compact cards (one primary column + key columns).
///
/// Pair with [BaseListController] for pagination/search/filters.
class AppTable<T> extends StatelessWidget {
  const AppTable({
    super.key,
    required this.columns,
    required this.items,
    required this.keyOf,
    this.info,
    this.isLoading = false,
    this.error,
    this.onRowTap,
    this.onPageChanged,
    this.onPageSizeChanged,
    this.onRefresh,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.leadingCell,
    this.mobileCards,
    this.onLoadMore,
    this.hasMore = false,
  });

  final List<AppColumn<T>> columns;
  final List<T> items;
  final String Function(T item) keyOf;
  final PageInfo? info;
  final bool isLoading;
  final String? error;
  final ValueChanged<T>? onRowTap;

  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final VoidCallback? onRefresh;

  final String emptyTitle;
  final String? emptyMessage;

  /// Current sort (desktop).
  final String? sortColumn;
  final bool sortAscending;
  final void Function(String field, bool ascending)? onSort;

  /// Optional leading cell (avatar, checkbox…).
  final Widget? Function(T item)? leadingCell;

  /// Mobile card builder; defaults to a compact two-line card.
  final Widget Function(BuildContext context, T item)? mobileCards;

  /// Infinite scroll support (list-style controllers).
  final VoidCallback? onLoadMore;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return const AppLoader();
    }
    if (error != null && items.isEmpty) {
      return AppErrorState(message: error!, onRetry: onRefresh);
    }
    if (items.isEmpty) {
      return AppEmptyState(
        title: emptyTitle,
        message: emptyMessage,
        onAction: onRefresh,
      );
    }
    if (context.isMobile) {
      return _buildMobile(context);
    }
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------ desktop

  Widget _buildDesktop(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AppColumn<T>> visible =
        columns.where((AppColumn<T> c) => c.visible).toList();

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                  theme.colorScheme.primary.withAlpha(18)),
              dataRowMinHeight: 46,
              dataRowMaxHeight: 56,
              headingRowHeight: 44,
              columns: <DataColumn>[
                for (int i = 0; i < visible.length; i++)
                  DataColumn(
                    label: _sortableHeader(context, visible[i], i),
                    numeric: visible[i].numeric,
                    tooltip: visible[i].tooltip,
                  ),
              ],
              rows: <DataRow>[
                for (final T item in items)
                  DataRow(
                    key: ValueKey<String>(keyOf(item)),
                    onSelectChanged:
                        onRowTap == null ? null : (_) => onRowTap!(item),
                    cells: <DataCell>[
                      for (final AppColumn<T> column in visible)
                        DataCell(
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: column.numeric
                                ? Align(
                                    alignment: Alignment.centerRight,
                                    child: column.value(item),
                                  )
                                : column.value(item),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (info != null && onPageChanged != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            child: AppPagination(
              info: info!,
              onPageChanged: onPageChanged!,
              onPageSizeChanged: onPageSizeChanged,
            ),
          ),
      ],
    );
  }

  Widget _sortableHeader(BuildContext context, AppColumn<T> column, int index) {
    final bool sortable = onSort != null && sortColumn != null;
    final bool active = sortable && sortColumn == column.label;
    return Tooltip(
      message: column.tooltip ?? 'Sort by ${column.label}',
      child: InkWell(
        onTap: onSort == null
            ? null
            : () => onSort!(
                column.label,
                active ? !sortAscending : true,
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(column.label,
                style: Theme.of(context).textTheme.labelMedium),
            if (active)
              Icon(
                sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- mobile

  Widget _buildMobile(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AppColumn<T>> keyCols = columns
        .where((AppColumn<T> c) => c.visible)
        .take(3)
        .toList();
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: items.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        if (index == items.length && hasMore) {
          onLoadMore?.call();
          return const Padding(
            padding: EdgeInsets.all(16),
            child: AppLoader(small: true),
          );
        }
        final T item = items[index];
        if (mobileCards != null) return mobileCards!(context, item);
        final Widget? leading =
            leadingCell != null ? leadingCell!(item) : null;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onRowTap == null ? null : () => onRowTap!(item),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  if (leading != null) ...<Widget>[
                    leading,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DefaultTextStyle(
                          style: (theme.textTheme.titleSmall ??
                                  const TextStyle(fontSize: 14))
                              .copyWith(),
                          child: _primaryLabel(context, item, keyCols),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: <Widget>[
                            for (int i = 1; i < keyCols.length; i++)
                              keyCols[i].value(item),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _primaryLabel(
      BuildContext context, T item, List<AppColumn<T>> keyCols) {
    if (keyCols.isEmpty) return const Text('');
    return keyCols.first.value(item);
  }
}

/// Convenience: converts raw column specs to widgets for the most common
/// cell types (text, money, status chip).
class TableCells {
  TableCells._();

  static Widget text(String value, {bool bold = false, Color? color}) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color,
      ),
    );
  }

  static Widget sub(String value) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
    );
  }
}
