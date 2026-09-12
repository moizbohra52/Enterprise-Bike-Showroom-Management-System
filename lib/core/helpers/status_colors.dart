import 'package:flutter/material.dart';

/// Maps wire status strings to consistent colors/icons used by
/// [AppStatusChip] and data grids.
class StatusColors {
  StatusColors._();

  static final Map<String, Color> _colors = <String, Color>{
    // Generic
    'active': const Color(0xFF16A34A),
    'available': const Color(0xFF16A34A),
    'completed': const Color(0xFF2563EB),
    'paid': const Color(0xFF16A34A),
    'closed': const Color(0xFF2563EB),
    'received': const Color(0xFF2563EB),
    'delivered': const Color(0xFF2563EB),
    'resolved': const Color(0xFF2563EB),
    'approved': const Color(0xFF16A34A),
    'success': const Color(0xFF16A34A),
    'sent': const Color(0xFF2563EB),
    'used': const Color(0xFF2563EB),
    'finalized': const Color(0xFF2563EB),
    'received_stock': const Color(0xFF2563EB),
    // Pending-ish
    'pending': const Color(0xFFD97706),
    'draft': const Color(0xFFD97706),
    'reserved': const Color(0xFFD97706),
    'booked': const Color(0xFFD97706),
    'upcoming': const Color(0xFFD97706),
    'due': const Color(0xFFD97706),
    'in_progress': const Color(0xFFD97706),
    'waiting_for_parts': const Color(0xFFD97706),
    'in_transit': const Color(0xFFD97706),
    'partial': const Color(0xFFD97706),
    'partially_paid': const Color(0xFFD97706),
    'ordered': const Color(0xFFD97706),
    'in_review': const Color(0xFFD97706),
    'open': const Color(0xFFD97706),
    'expiring_soon': const Color(0xFFD97706),
    'reducing': const Color(0xFF64748B),
    'flat': const Color(0xFF64748B),
    // Negative
    'cancelled': const Color(0xFFDC2626),
    'canceled': const Color(0xFFDC2626),
    'overdue': const Color(0xFFB91C1C),
    'overdue': const Color(0xFFB91C1C),
    'defaulted': const Color(0xFFB91C1C),
    'rejected': const Color(0xFFDC2626),
    'failed': const Color(0xFFDC2626),
    'voided': const Color(0xFFDC2626),
    'reversed': const Color(0xFF9333EA),
    'refunded': const Color(0xFF9333EA),
    'expired': const Color(0xFFB91C1C),
    'damaged': const Color(0xFFB91C1C),
    'scrapped': const Color(0xFF64748B),
    'blocked': const Color(0xFFDC2626),
    // Neutral
    'inactive': const Color(0xFF64748B),
    'returned': const Color(0xFF64748B),
    'transferred': const Color(0xFF64748B),
  };

  static final Map<String, IconData> _icons = <String, IconData>{
    'active': Icons.check_circle_outline,
    'available': Icons.check_circle_outline,
    'completed': Icons.task_alt,
    'paid': Icons.payments,
    'closed': Icons.lock,
    'delivered': Icons.delivery_dining,
    'approved': Icons.thumb_up,
    'pending': Icons.hourglass_bottom,
    'draft': Icons.edit_outlined,
    'reserved': Icons.bookmark_border,
    'booked': Icons.event,
    'upcoming': Icons.schedule,
    'due': Icons.alarm,
    'in_progress': Icons.autorenew,
    'waiting_for_parts': Icons.inventory_2_outlined,
    'in_transit': Icons.local_shipping,
    'partial': Icons.remove_moderator,
    'cancelled': Icons.cancel,
    'overdue': Icons.report_problem,
    'rejected': Icons.thumb_down,
    'failed': Icons.error_outline,
    'reversed': Icons.revert,
    'refunded': Icons.currency_exchange,
    'expired': Icons.event_busy,
    'expiring_soon': Icons.warning_amber,
    'inactive': Icons.pause_circle_outline,
    'damaged': Icons.construction,
    'blocked': Icons.block,
    'returned': Icons.replay,
    'transferred': Icons.swap_horiz,
    'defaulted': Icons.report_off,
    'voided': Icons.highlight_off,
    'open': Icons.folder_open,
    'in_review': Icons.visibility,
    'resolved': Icons.verified,
    'used': Icons.done_all,
    'sent': Icons.send,
    'finalized': Icons.gavel,
    'scrapped': Icons.delete_forever_outlined,
  };

  /// Color for a status string; [fallback] when unknown.
  static Color color(String? status, {Color? fallback}) {
    if (status == null || status.isEmpty) return fallback ?? Colors.grey;
    return _colors[status] ??
        _colors[status.toLowerCase().trim()] ??
        (fallback ?? Colors.blueGrey);
  }

  /// Icon for a status string; [fallback] when unknown.
  static IconData icon(String? status, {IconData? fallback}) {
    if (status == null || status.isEmpty) return fallback ?? Icons.circle_outlined;
    return _icons[status] ??
        _icons[status.toLowerCase().trim()] ??
        (fallback ?? Icons.circle_outlined);
  }
}
