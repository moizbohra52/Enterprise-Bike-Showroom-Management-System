import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:flutter/material.dart';

/// Convenience accessors on [BuildContext].
extension ContextX on BuildContext {
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;

  double get width => mediaQuery.size.width;
  double get height => mediaQuery.size.height;
  double get topPadding => mediaQuery.padding.top;
  double get bottomPadding => mediaQuery.padding.bottom;

  bool get isDesktop => width >= AppConfig.desktopBreakpoint;
  bool get isTablet => width >= AppConfig.tabletBreakpoint && !isDesktop;
  bool get isMobile => width < AppConfig.tabletBreakpoint;

  /// Responsive horizontal page padding.
  EdgeInsets get pagePadding => isDesktop
      ? const EdgeInsets.symmetric(horizontal: 24, vertical: 20)
      : const EdgeInsets.symmetric(horizontal: 12, vertical: 12);

  /// Shows a Material snackbar with the app theme.
  void showSnack(String message, {bool error = false}) {
    final ScaffoldFeatureController? controller =
        ScaffoldMessenger.of(this)
            .showSnackBar(SnackBar(
              content: Row(
                children: <Widget>[
                  Icon(
                    error ? Icons.error_outline : Icons.info_outline,
                    size: 18,
                    color: error ? colors.error : colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(message, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ));
    // ignore: unused_local_variable
    final _ = controller;
  }
}
