import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_empty_state.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_search_field.dart';
import 'package:enterprise_bike_showroom/core/extensions/context_extensions.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/search/controllers/search_controller.dart';
import 'package:enterprise_bike_showroom/features/search/models/search_result_model.dart';

/// Global search results screen (opened from the top bar).
///
/// The query lives on [GlobalSearchController] - a permanent singleton - so
/// the term (and the pre-fill from the top bar) survives navigation.
class GlobalSearchView extends StatefulWidget {
  const GlobalSearchView({super.key});

  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  late final TextEditingController _text =
      TextEditingController(text: Get.find<GlobalSearchController>().query.value);

  GlobalSearchController get _search => Get.find<GlobalSearchController>();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Search',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppCard(
                  padding: 12,
                  child: AppSearchField(
                    hint: 'Customers, chassis no, invoice no, mobile…',
                    controller: _text,
                    autofocus: true,
                    onSearch: (String q) => _search.query.value = q,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Obx(() {
                    if (_search.isLoading.value) {
                      return const AppLoader(message: 'Searching…');
                    }
                    final List<SearchResultModel> results =
                        _search.results.toList(growable: false);
                    if (_search.query.value.trim().length < 2) {
                      return const AppEmptyState(
                        icon: Icons.search,
                        title: 'Type at least 2 characters',
                        message: 'Search across customers, vehicles, stock, '
                            'sales, invoices, payments and job cards.',
                      );
                    }
                    if (results.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.search_off,
                        title: 'No matches',
                        message: 'Nothing matched '
                            '"${AppFormatters.truncate(_search.query.value, 40)}".',
                      );
                    }
                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) =>
                          _resultTile(context, results[index]),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultTile(BuildContext context, SearchResultModel r) {
    return AppCard(
      padding: 12,
      onTap: () => _search.open(r),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconFor(r.entityType),
              size: 20,
              color: context.colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  r.title,
                  style: context.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (r.subtitle != null && r.subtitle!.isNotEmpty)
                  Text(
                    r.subtitle!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            AppFormatters.humanize(r.entityType),
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String entityType) {
    switch (entityType) {
      case 'customer':
        return Icons.person_outline;
      case 'customer_vehicle':
      case 'vehicle':
        return Icons.two_wheeler_outlined;
      case 'product':
        return Icons.pedals_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'sale':
        return Icons.point_of_sale_outlined;
      case 'invoice':
        return Icons.receipt_long_outlined;
      case 'payment':
        return Icons.payments_outlined;
      case 'loan':
      case 'emi':
        return Icons.account_balance_outlined;
      case 'service':
      case 'service_record':
        return Icons.engineering_outlined;
      default:
        return Icons.search;
    }
  }
}
