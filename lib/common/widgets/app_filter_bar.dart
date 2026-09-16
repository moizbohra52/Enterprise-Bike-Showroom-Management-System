import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/common/models/dropdown_option.dart';

/// Horizontal filter strip; wraps on mobile, stays in a row on desktop.
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({super.key, this.children = const <Widget>[]});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// Small labelled filter chip with a dropdown (for enum-like filters).
class AppFilterDropdown<T> extends StatelessWidget {
  const AppFilterDropdown({
    super.key,
    required this.label,
    required this.options,
    this.value,
    required this.onChanged,
  });

  final String label;
  final List<DropdownOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: ButtonTheme(
        aligned: false,
        child: DropdownButton<T>(
          value: _inOptions() ? value : null,
          hint: Text(label),
          borderRadius: BorderRadius.circular(10),
          isDense: true,
          dropdownColor: Theme.of(context).canvasColor,
          items: <DropdownMenuItem<T>>[
            for (final DropdownOption<T> option in options)
              DropdownMenuItem<T>(
                value: option.value,
                child: Text(option.label, style: const TextStyle(fontSize: 13)),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  bool _inOptions() {
    if (value == null) return false;
    return options.any((DropdownOption<T> o) => o.value == value);
  }
}
