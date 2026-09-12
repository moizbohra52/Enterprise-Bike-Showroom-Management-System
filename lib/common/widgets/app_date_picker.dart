import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/core/utils/date_utils.dart';

/// Standard date picker input (tap to open, optional validator).
class AppDatePicker extends StatefulWidget {
  const AppDatePicker({
    super.key,
    this.value,
    this.onChanged,
    this.label,
    this.hint,
    this.helper,
    this.validator,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final String? label;
  final String? hint;
  final String? helper;
  final String? Function(DateTime?)? validator;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;

  @override
  State<AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<AppDatePicker> {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.enabled ? _pick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint ?? 'Select date',
          helperText: widget.helper,
          suffixIcon: const Icon(Icons.calendar_month_outlined),
        ),
        child: Text(
          DateUtils.format(widget.value),
          style: TextStyle(
            fontSize: 14,
            color: widget.value == null ? Theme.of(context).disabledColor : null,
          ),
        ),
      ),
    );
  }

  Future<void> _pick() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? now,
      firstDate: widget.firstDate ?? DateTime(now.year - 15),
      lastDate: widget.lastDate ?? DateTime(now.year + 15),
    );
    if (picked != null) {
      widget.onChanged?.call(picked);
    }
  }
}

/// Date range selector used by report/filter bars.
class AppDateRange extends StatefulWidget {
  const AppDateRange({
    super.key,
    this.start,
    this.end,
    required this.onChanged,
    this.label = 'Date range',
    this.firstDate,
    this.lastDate,
  });

  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime? start, DateTime? end) onChanged;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<AppDateRange> createState() => _AppDateRangeState();
}

class _AppDateRangeState extends State<AppDateRange> {
  @override
  Widget build(BuildContext context) {
    final bool filled = widget.start != null && widget.end != null;
    return InkWell(
      onTap: _pick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'From – To',
          suffixIcon: const Icon(Icons.date_range_outlined),
        ),
        child: Text(
          filled
              ? '${DateUtils.format(widget.start)} – ${DateUtils.format(widget.end)}'
              : '',
          style: TextStyle(
            fontSize: 14,
            color: filled ? null : Theme.of(context).disabledColor,
          ),
        ),
      ),
    );
  }

  Future<void> _pick() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: widget.firstDate ?? DateTime(now.year - 5),
      lastDate: widget.lastDate ?? now.add(const Duration(days: 1)),
      initialStartDate: widget.start,
      initialEndDate: widget.end,
    );
    if (range != null) {
      widget.onChanged(range.start, range.end);
    }
  }
}
