import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';

/// Standard dropdown. Use [AppSearchDropdown] for very long lists.
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.helper,
    this.validator,
    this.enabled = true,
    this.autofocus = false,
  });

  final List<DropdownOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final String? helper;
  final String? Function(T?)? validator;
  final bool enabled;
  final bool autofocus;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: _valueInOptions() ? widget.value : null,
      onChanged: widget.enabled ? widget.onChanged : null,
      autofocus: widget.autofocus,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
      ),
      validator: widget.validator,
      items: <DropdownMenuItem<T>>[
        for (final DropdownOption<T> option in widget.options)
          DropdownMenuItem<T>(
            value: option.value,
            child: Text(option.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14)),
          ),
      ],
    );
  }

  bool _valueInOptions() {
    if (widget.value == null) return false;
    return widget.options.any(
      (DropdownOption<T> o) => o.value == widget.value,
    );
  }
}

/// Searchable dropdown for large option sets (uses a dialog).
class AppSearchDropdown<T> extends StatefulWidget {
  const AppSearchDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.placeholder = 'Select…',
    this.enabled = true,
  });

  final List<DropdownOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final String placeholder;
  final bool enabled;

  @override
  State<AppSearchDropdown<T>> createState() => _AppSearchDropdownState<T>();
}

class _AppSearchDropdownState<T> extends State<AppSearchDropdown<T>> {
  final TextEditingController _search = TextEditingController();
  List<DropdownOption<T>> _filtered = <DropdownOption<T>>[];

  String? get _selectedLabel {
    if (widget.value == null) return null;
    for (final DropdownOption<T> o in widget.options) {
      if (o.value == widget.value) return o.label;
    }
    return null;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.enabled ? _openPicker : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _selectedLabel ?? widget.placeholder,
                style: TextStyle(
                  fontSize: 14,
                  color: _selectedLabel == null
                      ? Theme.of(context).disabledColor
                      : null,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker() async {
    _filtered = widget.options;
    final T? picked = await showDialog<T>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _PickerDialog<T>(search: _search, options: _filtered),
    );
    if (picked != null && picked != widget.value) {
      widget.onChanged?.call(picked);
    }
  }
}

class _PickerDialog<T> extends StatefulWidget {
  const _PickerDialog({required this.search, required this.options});

  final TextEditingController search;
  final List<DropdownOption<T>> options;

  @override
  State<_PickerDialog<T>> createState() => _PickerDialogState<T>();
}

class _PickerDialogState<T> extends State<_PickerDialog<T>> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearch);
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearch);
    super.dispose();
  }

  void _onSearch() {
    setState(() => _query = widget.search.text.toLowerCase());
  }

  List<DropdownOption<T>> get _visible {
    if (_query.isEmpty) return widget.options;
    return widget.options
        .where((DropdownOption<T> o) =>
            o.label.toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: widget.search,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _visible.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No matches')),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final DropdownOption<T> option in _visible.take(100))
                          ListTile(
                            title: Text(option.label),
                            subtitle:
                                option.hint != null ? Text(option.hint!) : null,
                            onTap: () {
                              // The owning state reads selection through
                              // onChanged; find the host via its controller.
                              _pick(option);
                            },
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  void _pick(DropdownOption<T> option) {
    Navigator.of(context).pop(option.value);
  }
}
