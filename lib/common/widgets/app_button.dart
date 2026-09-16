import 'package:flutter/material.dart';

/// Button variants.
enum AppButtonVariant { filled, outlined, text, danger, tonal }

/// Size presets.
enum AppButtonSize { small, medium, large }

/// The application's standard button (Material 3 friendly).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.size = AppButtonSize.medium,
    this.isLoading = false,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool isLoading;
  final IconData? icon;
  final bool expanded;

  /// Icon-only convenience constructor.
  const AppButton.icon({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.outlined,
    this.size = AppButtonSize.small,
    this.isLoading = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final double h = switch (size) {
      AppButtonSize.small => 34,
      AppButtonSize.medium => 42,
      AppButtonSize.large => 50,
    };
    final double fontSize =
        size == AppButtonSize.small ? 13 : size == AppButtonSize.large ? 15 : 14;

    final Widget child = isLoading
        ? SizedBox(
            width: h * 0.45,
            height: h * 0.45,
            child: const CircularProgressIndicator(strokeWidth: 2.2),
          )
        : Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: fontSize + 4),
                const SizedBox(width: 8),
              ],
              Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          );

    final Widget inner = Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 0 : (icon != null ? 12 : 20), vertical: 0),
      child: child,
    );

    switch (variant) {
      case AppButtonVariant.filled:
        return SizedBox(
          height: h,
          width: expanded ? double.infinity : null,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: colors.primary,
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              textStyle:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
            child: inner,
          ),
        );
      case AppButtonVariant.danger:
        return SizedBox(
          height: h,
          width: expanded ? double.infinity : null,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFFDC2626),
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              textStyle:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
            child: inner,
          ),
        );
      case AppButtonVariant.tonal:
        return SizedBox(
          height: h,
          width: expanded ? double.infinity : null,
          child: FilledButton.tonal(
            onPressed: isLoading ? null : onPressed,
            style: FilledButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              textStyle:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
            child: inner,
          ),
        );
      case AppButtonVariant.outlined:
        return SizedBox(
          height: h,
          width: expanded ? double.infinity : null,
          child: OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              textStyle:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
            child: inner,
          ),
        );
      case AppButtonVariant.text:
        return SizedBox(
          height: h,
          width: expanded ? double.infinity : null,
          child: TextButton(
            onPressed: isLoading ? null : onPressed,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              textStyle:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
            child: inner,
          ),
        );
    }
  }
}
