import 'dart:math' as math;

import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';

/// Numeric conveniences.
extension NumX on num {
  /// Rounds to 2 decimals (money).
  num get money => (this * 100).roundToDouble() / 100;

  /// Rounds to `digits` decimals.
  num roundTo(int digits) {
    final double factor = math.pow(10, digits).toDouble();
    return (toDouble() * factor).roundToDouble() / factor;
  }

  double get asDouble => toDouble();
  int get asInt => toInt();

  /// `1234567` -> `₹ 12,34,567.00`
  String get currency => AppFormatters.currency(this);

  /// `1234567` -> `1,23,4567`
  String get grouped => AppFormatters.amount(this);

  /// `18.5` -> `18.5 %`
  String get percent => AppFormatters.percent(this);
}
