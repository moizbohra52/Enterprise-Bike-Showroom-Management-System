import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// Input parameters for a server-side paginated query.
///
/// Pages are 1-based; the repository converts [page] into Postgres
/// `range(offset, limit-1)` windows.
class PageQuery {
  PageQuery({
    this.page = 1,
    this.pageSize = AppConfig.defaultPageSize,
    this.search,
    this.filters = const <String, dynamic>{},
    this.orderBy,
    this.ascending = true,
  });

  /// Current page (1-based).
  final int page;

  /// Rows per page (default [AppConfig.defaultPageSize]).
  final int pageSize;

  /// Free-text search term (debounced on the UI side).
  final String? search;

  /// Structured filters, e.g. `status`, `from_date`, `to_date`,
  /// `showroom_id`, `customer_id`.
  final Map<String, dynamic> filters;

  /// Field used for ordering.
  final String? orderBy;

  /// Sort direction.
  final bool ascending;

  /// Zero-based offset for `range()`.
  int get offset => ((page - 1) < 0 ? 0 : (page - 1)) * pageSize;

  /// Inclusive end of the range window.
  int get end => offset + pageSize - 1;

  PageQuery copyWith({
    int? page,
    int? pageSize,
    String? search,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool? ascending,
    bool clearSearch = false,
  }) {
    return PageQuery(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: clearSearch ? null : (search ?? this.search),
      filters: filters ?? this.filters,
      orderBy: orderBy ?? this.orderBy,
      ascending: ascending ?? this.ascending,
    );
  }
}

/// Pagination metadata returned by the server (exact count).
class PageInfo {
  const PageInfo({
    required this.page,
    required this.pageSize,
    required this.total,
  });

  const PageInfo.empty()
      : page = 1,
        pageSize = AppConfig.defaultPageSize,
        total = 0;

  final int page;
  final int pageSize;
  final int total;

  int get totalPages =>
      pageSize <= 0 ? 0 : (total / pageSize).ceil().clamp(1, 1 << 31);

  bool get hasNext => page < totalPages;

  factory PageInfo.fromJson(Map<String, dynamic> json) {
    return PageInfo(
      page: SafeJson.asIntOr(json['page'], 1),
      pageSize: SafeJson.asIntOr(json['page_size'], AppConfig.defaultPageSize),
      total: SafeJson.asIntOr(json['total'], 0),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'page': page,
        'page_size': pageSize,
        'total': total,
      };
}

/// A page of results plus its pagination metadata.
class PaginatedResponse<T> {
  const PaginatedResponse({required this.items, required this.info});

  final List<T> items;
  final PageInfo info;

  factory PaginatedResponse.fromSupabase<T>(
    List<dynamic> data, {
    required int total,
    required PageQuery query,
    required T Function(Map<String, dynamic>) fromJson,
  }) {
    final List<T> items = <T>[
      for (final dynamic row in data)
        if (row is Map<String, dynamic>) fromJson(row),
    ];
    return PaginatedResponse<T>(
      items: items,
      info: PageInfo(page: query.page, pageSize: query.pageSize, total: total),
    );
  }

  PaginatedResponse<T> copyWithItems(List<T> newItems) {
    return PaginatedResponse<T>(items: newItems, info: info);
  }
}
