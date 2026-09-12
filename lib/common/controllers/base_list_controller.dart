import 'dart:async';

import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';

/// Holds mutable query state for [BaseListController].
class ListQueryState {
  ListQueryState({this.pageSize = AppConfig.defaultPageSize});

  int page = 1;
  String? search;
  Map<String, dynamic> filters = <String, dynamic>{};
  String? orderBy;
  bool ascending = true;
  int pageSize;

  PageQuery toQuery() {
    return PageQuery(
      page: page,
      pageSize: pageSize,
      search: (search == null || search!.trim().isEmpty)
          ? null
          : search!.trim(),
      filters: Map<String, dynamic>.of(filters),
      orderBy: orderBy,
      ascending: ascending,
    );
  }
}

/// Generic paginated list controller.
///
/// Subclasses pass a `loader` function (repository list method) and get
/// reactive `items`, `isLoading`, `errorMessage`, `pageInfo`, search
/// debouncing, filters, sorting and pagination for free.
class BaseListController<T> extends GetxController {
  BaseListController(
    this.loader, {
    int pageSize = AppConfig.defaultPageSize,
  }) {
    state.pageSize = pageSize;
  }

  /// Loads one page: `query -> List<T>`.
  final Future<List<T>> Function(PageQuery query) loader;

  /// Mutable query state.
  final ListQueryState state = ListQueryState();

  final RxList<T> items = <T>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;
  final Rx<PageInfo> pageInfo = const Rx<PageInfo>(PageInfo.empty());
  final RxBool hasMore = false.obs;

  /// Active debounced search text (bound to AppSearchField).
  final RxString search = ''.obs;

  Timer? _searchTimer;

  /// Runs the current query on page 1 (refresh).
  Future<void> refresh() async {
    state.page = 1;
    await _run();
  }

  /// Next page (used by pagination controls).
  Future<void> nextPage() async {
    state.page += 1;
    await _run();
  }

  /// Previous page.
  Future<void> previousPage() async {
    if (state.page > 1) state.page -= 1;
    await _run();
  }

  Future<void> goToPage(int page) async {
    state.page = page;
    await _run();
  }

  /// Appends the next page to existing items (infinite scroll).
  Future<void> loadMore() async {
    if (!hasMore.value || isLoading.value) return;
    state.page += 1;
    final bool append = true;
    await _run(append: append);
  }

  /// Debounced search update.
  void updateSearch(String value) {
    search.value = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: AppConfig.searchDebounceMs),
        () {
      state.search = value.isEmpty ? null : value;
      state.page = 1;
      unawaited(_run());
    });
  }

  /// Sets a structured filter (null removes it).
  void setFilter(String key, dynamic value) {
    if (value == null ||
        value == false ||
        (value is String && value.isEmpty)) {
      state.filters.remove(key);
    } else {
      state.filters[key] = value;
    }
    state.page = 1;
    unawaited(_run());
  }

  void setFilters(Map<String, dynamic> filters) {
    state.filters = Map<String, dynamic>.of(filters);
    state.page = 1;
    unawaited(_run());
  }

  void clearFilters() {
    state.filters = <String, dynamic>{};
    state.search = null;
    search.value = '';
    state.page = 1;
    unawaited(_run());
  }

  /// Sets ordering (desktop column sort).
  void setOrderBy(String field, bool ascending) {
    state.orderBy = field;
    state.ascending = ascending;
    state.page = 1;
    unawaited(_run());
  }

  void setPageSize(int size) {
    state.pageSize = size;
    state.page = 1;
    unawaited(_run());
  }

  Future<void> _run({bool append = false}) async {
    if (isLoading.value) return;
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final PageQuery query = state.toQuery();
      final List<T> rows = await loader(query);
      if (append) {
        items.addAll(rows);
      } else {
        items.assignAll(rows);
      }
      // Loader returns a plain list; total info is supplied via the
      // controller's `setPageInfo` hook by repositories that know the count.
      hasMore.value = rows.length >= query.pageSize;
    } on AppException catch (e) {
      errorMessage.value = e.message;
      AppLogger.error('LIST', e.message, error: e.details);
    } catch (e) {
      final AppException mapped = ErrorMapper.map(e);
      errorMessage.value = mapped.message;
      AppLogger.error('LIST', mapped.message, error: e);
    } finally {
      isLoading.value = false;
    }
  }

  /// Repositories/controllers expose totals through this hook.
  void setPageInfo(PageInfo info) {
    pageInfo.value = info;
    hasMore.value = info.hasNext;
  }

  @override
  void onClose() {
    _searchTimer?.cancel();
    super.onClose();
  }
}
