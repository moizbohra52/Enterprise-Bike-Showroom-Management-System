import 'package:enterprise_bike_showroom/config/app_config.dart';
import 'package:intl/intl.dart';

/// Centralized display formatting. Widgets never format numbers/dates
/// themselves - they call [AppFormatters].
class AppFormatters {
  AppFormatters._();

  static final NumberFormat _currencyFormat =
      NumberFormat('#,##0.00', 'en_IN');
  static final NumberFormat _numberFormat =
      NumberFormat('#,##0', 'en_IN');
  static final NumberFormat _decimalFormat = NumberFormat('#,##0.####');

  /// `₹ 1,23,456.00` (Indian grouping).
  static String currency(num value, {String? symbol}) {
    final String s = symbol ?? AppConfig.currencySymbol;
    return '$s ${_currencyFormat.format(value)}';
  }

  /// Currency without the symbol (used in data grids).
  static String amount(num value) => _currencyFormat.format(value);

  /// Plain grouped number.
  static String number(num value) => _numberFormat.format(value);

  /// Compact Indian-style money: `1.24L`, `3.5Cr`, `85K`.
  static String compactMoney(num value) {
    final num abs = value.abs();
    final String sign = value.isNegative ? '-' : '';
    if (abs >= 10000000) return '${sign}${_decimalFormat.format(abs / 10000000)}Cr';
    if (abs >= 100000) return '${sign}${_decimalFormat.format(abs / 100000)}L';
    if (abs >= 1000) return '${sign}${_decimalFormat.format(abs / 1000)}K';
    return '${sign}${_numberFormat.format(abs)}';
  }

  /// `18.5 %`.
  static String percent(num value, {int decimals = 1}) {
    final NumberFormat f = NumberFormat('#,##0.${'0' * decimals}');
    return '${f.format(value)} %';
  }

  /// `dd MMM yyyy`.
  static String date(dynamic value) {
    if (value == null) return '-';
    DateTime? d;
    if (value is DateTime) {
      d = value;
    } else {
      d = DateTime.tryParse(value.toString());
    }
    if (d == null) return value.toString();
    return DateFormat('dd MMM yyyy').format(d);
  }

  /// `dd MMM yyyy HH:mm`.
  static String dateTime(dynamic value) {
    if (value == null) return '-';
    DateTime? d = value is DateTime ? value : DateTime.tryParse(value.toString());
    if (d == null) return value.toString();
    return DateFormat('dd MMM yyyy HH:mm').format(d);
  }

  /// `+91 98765 43210` (best-effort formatting).
  static String phone(String? value) {
    if (value == null || value.trim().isEmpty) return '-';
    final String digits =
        value.replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.length == 10) {
      return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
    }
    return value;
  }

  /// `1.5 km` / `1500 km`.
  static String km(num value) => '${number(value)} km';

  /// Truncates long text with an ellipsis.
  static String truncate(String? value, int length) {
    if (value == null) return '';
    if (value.length <= length) return value;
    return '${value.substring(0, length)}…';
  }

  /// Uppercase first letter.
  static String capitalize(String? value) {
    if (value == null || value.isEmpty) return value ?? '';
    return value[0].toUpperCase() + value.substring(1);
  }

  /// `available` -> `Available`.
  static String humanize(String? value) {
    if (value == null || value.isEmpty) return '-';
    final String s = value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
    return s.split(' ').map(capitalize).join(' ');
  }
}
