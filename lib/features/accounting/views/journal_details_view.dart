import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:enterprise_bike_showroom/common/layouts/app_shell.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_card.dart';
import 'package:enterprise_bike_showroom/common/widgets/app_loader.dart';
import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/features/accounting/controllers/accounting_controller.dart';
import 'package:enterprise_bike_showroom/features/accounting/models/accounting_models.dart';

/// Journal entry detail (debit / credit lines).
class JournalDetailsView extends GetView<JournalDetailsController> {
  const JournalDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final String? id = Get.parameters['id'] ?? _pathId();
    if (id == null) {
      return AppShell(
          title: 'Journal', showBack: true, child: const AppLoader());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.load(id));

    return AppShell(
      title: 'Journal Entry',
      showBack: true,
      child: Obx(() {
        if (controller.isLoading.value || controller.entry.value == null) {
          return const AppLoader();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _body(controller.entry.value!),
        );
      }),
    );
  }

  String? _pathId() {
    final String? name = Get.currentRoute;
    if (name != null) {
      final List<String> parts = name.split('/');
      if (parts.isNotEmpty) return parts.last;
    }
    return null;
  }

  Widget _body(JournalEntryModel entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(entry.entryNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${AppFormatters.date(entry.entryDate)} · '
                    '${AppFormatters.humanize(entry.sourceModule ?? 'manual')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: entry.balanced
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                entry.balanced ? 'Balanced' : 'UNBALANCED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: entry.balanced
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (entry.narration.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('“${entry.narration}”',
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
          ),
        AppCard(
          title: 'Lines',
          child: Column(
            children: <Widget>[
              for (final JournalLineModel line in entry.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 70,
                        child: Text(line.accountCode,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text(line.accountName,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                            line.side == 'debit'
                                ? line.amount.currency
                                : '',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                            line.side == 'credit'
                                ? line.amount.currency
                                : '',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: line.side == 'debit'
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          line.side == 'debit' ? 'DR' : 'CR',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: line.side == 'debit'
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626)),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 16),
              _total('Total Debit', entry.totalDebit),
              _total('Total Credit', entry.totalCredit),
            ],
          ),
        ),
      ],
    );
  }

  Widget _total(String label, num value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value.currency,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
