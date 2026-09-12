import 'dart:async';

import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/config/app_config.dart';

/// Debounced search field. Emits [onSearch] after the user stops typing.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.onSearch,
    this.hint = 'Search…',
    this.controller,
    this.debounceMs = AppConfig.searchDebounceMs,
    this.focusNode,
    this.autofocus = false,
    this.leading = const Icon(Icons.search),
  });

  final ValueChanged<String>? onSearch;
  final String hint;
  final TextEditingController? controller;
  final int debounceMs;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget leading;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: widget.debounceMs), () {
      widget.onSearch?.call(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onChanged: _onChanged,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: widget.leading,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _controller.clear();
                  _onChanged('');
                },
              ),
      ),
    );
  }
}
