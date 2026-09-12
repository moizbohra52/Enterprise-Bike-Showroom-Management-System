import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/core/helpers/status_colors.dart';

/// Centralized snackbar helper. Works from anywhere (uses `Get.context`
/// via the provided context or a root context fallback).
class AppSnackbar {
  AppSnackbar._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackbarType type = AppSnackbarType.info,
    int durationSeconds = 3,
  }) {
    if (!context.mounted) return;
    final ScaffoldFeatureController? controller = ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
      content: Row(
        children: <Widget>[
          Icon(_iconFor(type), size: 18, color: _colorFor(type, context)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: durationSeconds),
    ));
    // ignore: unused_local_variable
    final _ = controller;
  }

  static void success(BuildContext context, String message) =>
      show(context, message, type: AppSnackbarType.success);

  static void error(BuildContext context, String message) =>
      show(context, message, type: AppSnackbarType.error);

  static void warning(BuildContext context, String message) =>
      show(context, message, type: AppSnackbarType.warning);

  static void info(BuildContext context, String message) =>
      show(context, message, type: AppSnackbarType.info);

  static IconData _iconFor(AppSnackbarType type) {
    switch (type) {
      case AppSnackbarType.success:
        return Icons.check_circle_outline;
      case AppSnackbarType.error:
        return Icons.error_outline;
      case AppSnackbarType.warning:
        return Icons.warning_amber_outlined;
      case AppSnackbarType.info:
        return Icons.info_outline;
    }
  }

  static Color _colorFor(AppSnackbarType type, BuildContext context) {
    switch (type) {
      case AppSnackbarType.success:
        return StatusColors.color('active');
      case AppSnackbarType.error:
        return StatusColors.color('cancelled');
      case AppSnackbarType.warning:
        return StatusColors.color('pending');
      case AppSnackbarType.info:
        return StatusColors.color('completed');
    }
  }
}

enum AppSnackbarType { info, success, error, warning }
