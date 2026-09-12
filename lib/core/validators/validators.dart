import 'package:enterprise_bike_showroom/core/utils/date_utils.dart';

/// Centralized form validation.
///
/// These validators mirror (but never replace) the database constraints and
/// Postgres check constraints defined in the migrations.
class AppValidators {
  AppValidators._();

  static String? required(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'This field is required.';
    }
    return null;
  }

  static String? requiredNum(num? value, {String? message}) {
    if (value == null) return message ?? 'This field is required.';
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final String v = value.trim();
    final bool ok = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(v);
    return ok ? null : 'Enter a valid email address.';
  }

  /// 10-digit Indian mobile number (optional leading 91/+91).
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required.';
    final String v = value.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    final String digits = v.startsWith('+') ? v.substring(1) : v;
    final bool ok = RegExp(r'^(91)?[6-9]\d{9}$').hasMatch(digits);
    return ok ? null : 'Enter a valid 10-digit mobile number.';
  }

  static String? optionalPhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return phone(value);
  }

  /// 15-character GSTIN (state code + PAN + entity + check digit).
  static String? gst(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final String v = value.trim().toUpperCase();
    final bool ok = RegExp(
      r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$',
    ).hasMatch(v);
    return ok ? null : 'Enter a valid 15-character GST number.';
  }

  /// 10-character PAN.
  static String? pan(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final String v = value.trim().toUpperCase();
    final bool ok =
        RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(v);
    return ok ? null : 'Enter a valid PAN.';
  }

  /// 6-digit Indian pincode.
  static String? pincode(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final String v = value.trim();
    final bool ok = RegExp(r'^[1-9][0-9]{5}$').hasMatch(v);
    return ok ? null : 'Enter a valid 6-digit pincode.';
  }

  static String? positiveAmount(num? value, {String? message}) {
    if (value == null) return message ?? 'Enter an amount.';
    if (value <= 0) return 'Amount must be greater than zero.';
    return null;
  }

  static String? nonNegativeAmount(num? value, {String? message}) {
    if (value == null) return message ?? 'Enter an amount.';
    if (value < 0) return 'Amount cannot be negative.';
    return null;
  }

  static String? optionalAmount(num? value) {
    if (value == null) return null;
    return nonNegativeAmount(value);
  }

  static String? between(num? value, num min, num max, {String? message}) {
    if (value == null) return null;
    if (value < min || value > max) {
      return message ?? 'Value must be between $min and $max.';
    }
    return null;
  }

  static String? requiredDate(DateTime? value, {String? message}) {
    if (value == null) return message ?? 'Select a date.';
    return null;
  }

  static String? dateNotInFuture(DateTime? value, {String? message}) {
    if (value == null) return null;
    if (DateUtils.startOfDay(value).isAfter(DateUtils.startOfDay(DateTime.now()))) {
      return message ?? 'Date cannot be in the future.';
    }
    return null;
  }

  static String? dateAfter(
    DateTime? value,
    DateTime after, {
    String? message,
  }) {
    if (value == null) return null;
    if (DateUtils.startOfDay(value).isBefore(DateUtils.startOfDay(after))) {
      return message ?? 'Date must be after ${DateUtils.format(after)}.';
    }
    return null;
  }

  /// Chassis number: 11-17 alphanumeric characters (VIN-like).
  static String? chassisNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Chassis number is required.';
    }
    final String v = value.trim().toUpperCase();
    final bool ok = RegExp(r'^[A-HJ-NPR-Z0-9]{11,17}$').hasMatch(v);
    return ok ? null : 'Enter a valid chassis number (11-17 characters).';
  }

  /// Engine number: 6-30 alphanumeric characters.
  static String? engineNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Engine number is required.';
    }
    final String v = value.trim().toUpperCase();
    final bool ok = RegExp(r'^[A-Z0-9]{6,30}$').hasMatch(v);
    return ok ? null : 'Enter a valid engine number.';
  }

  /// Indian vehicle registration, e.g. `GJ01 AB 1234`.
  static String? registrationNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final String v = value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    final bool ok =
        RegExp(r'^[A-Z]{2}\s?\d{1,2}\s?[A-Z]{1,2}\s?\d{4}$').hasMatch(v);
    return ok ? null : 'Enter a valid registration number.';
  }

  static String? minLength(String? value, int length, {String? message}) {
    if (value == null) return null;
    if (value.trim().length < length) {
      return message ?? 'Minimum $length characters required.';
    }
    return null;
  }

  static String? maxLength(String? value, int length, {String? message}) {
    if (value == null) return null;
    if (value.trim().length > length) {
      return message ?? 'Maximum $length characters allowed.';
    }
    return null;
  }

  /// Runs a list of validators and returns the first failure.
  static String? firstError(String? value,
      List<String? Function(String?)> validators) {
    for (final String? Function(String?) validator in validators) {
      final String? error = validator(value);
      if (error != null) return error;
    }
    return null;
  }
}
