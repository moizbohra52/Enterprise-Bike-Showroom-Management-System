import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/common/widgets/app_button.dart';

/// Reusable dialogs.
class AppDialog {
  AppDialog._();

  /// Simple alert with one OK button.
  static Future<void> show(
    BuildContext context, {
    required String title,
    String? message,
    String okLabel = 'OK',
    IconData icon = Icons.info_outline,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: Icon(icon, size: 40,
            color: Theme.of(dialogContext).colorScheme.primary),
        title: Text(title),
        content: message != null ? Text(message) : null,
        actions: <Widget>[
          AppButton(
            label: okLabel,
            size: AppButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  /// Confirm (destructive-aware) dialog. Returns true when confirmed.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: message != null ? Text(message) : null,
        actions: <Widget>[
          AppButton(
            label: cancelLabel,
            variant: AppButtonVariant.text,
            size: AppButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: confirmLabel,
            variant:
                destructive ? AppButtonVariant.danger : AppButtonVariant.filled,
            size: AppButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Text-input dialog. Returns the entered text (trimmed) or null.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    String? errorLabel,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) async {
    final TextEditingController controller = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (message != null && message.isNotEmpty) ...<Widget>[
                Text(message),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: keyboardType,
                maxLines: maxLines,
                decoration: InputDecoration(
                  labelText: hint ?? 'Enter value',
                  errorText: errorLabel,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          AppButton(
            label: cancelLabel,
            variant: AppButtonVariant.text,
            size: AppButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          AppButton(
            label: confirmLabel,
            size: AppButtonSize.small,
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    return (result == null || result.isEmpty) ? null : result;
  }

  /// Bottom-anchored dialog (works well on desktop & mobile).
  static Future<T?> bottomSheet<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    double expand = 0.75,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * expand,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}
