import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Standard form text field with validation + optional prefix/suffix.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helper,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.suffixText,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.onSubmitted,
    this.onChanged,
    this.onTap,
    this.inputFormatters,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.semanticLabel,
  });

  final TextEditingController? controller;

  /// Seed text when no [controller] is supplied (FormField-style).
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helper;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final String? prefixText;
  final String? suffixText;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final TextAlign textAlign;

  /// Accessibility label (defaults to [label]).
  final String? semanticLabel;

  @override
  State<AppTextField> createState() => AppTextFieldState();
}

/// Exposes the underlying [TextEditingController] and [FocusNode].
class AppTextFieldState extends State<AppTextField> {
  TextEditingController? _controller;
  late FocusNode focusNode;
  bool _obscured = true;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller;
      _ownsController = false;
    } else {
      _controller = TextEditingController(text: widget.initialValue);
      _ownsController = true;
    }
    focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) {
        _controller?.dispose();
      }
      if (widget.controller != null) {
        _controller = widget.controller;
        _ownsController = false;
      } else {
        _controller = TextEditingController(
          text: widget.initialValue ?? _controller?.text,
        );
        _ownsController = true;
      }
    } else if (widget.controller == null &&
        widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != null &&
        (_controller?.text.isEmpty ?? true)) {
      _controller?.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller?.dispose();
    }
    focusNode.dispose();
    super.dispose();
  }

  TextEditingController get controller => _controller!;
  String get text => _controller?.text ?? '';
  void clear() => _controller?.clear();

  void requestFocus() => FocusScope.of(context).requestFocus(focusNode);

  @override
  Widget build(BuildContext context) {
    final bool canObscure = widget.obscureText;
    return Semantics(
      label: widget.semanticLabel ?? widget.label,
      child: TextFormField(
        controller: _controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        obscureText: canObscure && _obscured,
        autofillHints:
            canObscure ? const <String>[AutofillHints.password] : null,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        maxLines: canObscure ? 1 : widget.maxLines,
        maxLength: widget.maxLength,
        autofocus: widget.autofocus,
        textAlign: widget.textAlign,
        inputFormatters: widget.inputFormatters,
        onFieldSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        onTap: widget.onTap,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          helperText: widget.helper,
          prefixIcon:
              widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
          prefixText: widget.prefixText,
          suffixIcon: canObscure
              ? IconButton(
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : (widget.suffixIcon != null ? Icon(widget.suffixIcon) : null),
          suffixText: widget.suffixText,
        ),
      ),
    );
  }
}
