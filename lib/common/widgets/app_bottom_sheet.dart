import 'package:flutter/material.dart';

/// Standalone bottom sheet helper (separate from [AppDialog] for direct
/// access to the sheet context).
class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    bool scroll = true,
    double expand = 0.8,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: expand,
          builder: (BuildContext innerContext, ScrollController controller) {
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(title,
                            style:
                                Theme.of(innerContext).textTheme.titleLarge),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(innerContext).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: scroll
                      ? ListView(
                          controller: controller,
                          padding: const EdgeInsets.all(16),
                          children: <Widget>[child],
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: child,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
