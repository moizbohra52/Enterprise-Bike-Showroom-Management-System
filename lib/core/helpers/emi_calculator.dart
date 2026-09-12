import 'dart:math' as math;

import 'package:enterprise_bike_showroom/core/enums/finance_enums.dart';

/// Client-side EMI math used for previews only.
///
/// The **server** (`calculate_emi` RPC + `generate_emi_schedule`) is the
/// single source of truth: reducing balance with the last installment
/// balancing to the exact total (flat: `principal + totalInterest / n`).
/// This class mirrors that behaviour so the sale form can show live
/// numbers while offline.
class EmiCalculator {
  EmiCalculator._();

  /// Monthly EMI for [principal] at [annualRatePercent] for [months].
  ///
  /// Reducing: standard amortisation formula.
  /// Flat: `(principal + principal * rate% * years) / months`.
  static num monthlyEmi(
    num principal,
    num annualRatePercent,
    int months, {
    InterestType method = InterestType.reducing,
  }) {
    if (months <= 0 || principal <= 0) return 0;
    if (method == InterestType.flat) {
      final num years = months / 12;
      final num totalInterest = principal * (annualRatePercent / 100) * years;
      return ((principal + totalInterest) / months).money2();
    }
    final double r = annualRatePercent / 100 / 12;
    if (r == 0) return (principal / months).money2();
    final double factor = math.pow(1 + r, months).toDouble();
    return (principal.toDouble() * r * factor / (factor - 1)).money2();
  }

  /// Total of all installments (final installment balances the sum).
  static num totalEmi(
    num principal,
    num annualRatePercent,
    int months, {
    InterestType method = InterestType.reducing,
  }) {
    if (months <= 0 || principal <= 0) return principal.money2();
    if (method == InterestType.flat) {
      final num years = months / 12;
      return (principal +
              principal * (annualRatePercent / 100) * years)
          .money2();
    }
    final num emi = monthlyEmi(principal, annualRatePercent, months);
    return (emi * months).money2();
  }

  /// One schedule row: balance before, interest, principal, balance after.
  static Map<String, num> installment({
    required num principal,
    required num annualRatePercent,
    required int month,
    required int months,
    required num emi,
    required num balanceBefore,
    InterestType method = InterestType.reducing,
  }) {
    if (method == InterestType.flat) {
      final num totalInterest =
          principal * (annualRatePercent / 100) * (months / 12);
      final num interest = (totalInterest / months).money2();
      final num principalPart = month == months
          ? balanceBefore - interest
          : (emi - interest).money2();
      return <String, num>{
        'interest': interest,
        'principal': principalPart.money2(),
        'balance': (balanceBefore - principalPart).money2(),
      };
    }
    final double rate = annualRatePercent / 100 / 12;
    final num interest = (balanceBefore.toDouble() * rate).money2();
    final num principalPart =
        month == months ? balanceBefore - interest : (emi - interest).money2();
    return <String, num>{
      'interest': interest,
      'principal': principalPart.money2(),
      'balance': (balanceBefore - principalPart).money2(),
    };
  }

  /// Total interest over the loan life (preview).
  static num totalInterest(
    num principal,
    num annualRatePercent,
    int months, {
    InterestType method = InterestType.reducing,
  }) {
    return (totalEmi(principal, annualRatePercent, months, method: method) -
            principal)
        .money2();
  }
}

/// Two-decimal money rounding shared by the calculator.
extension _Money2 on num {
  num money2() => (this * 100).roundToDouble() / 100;
}
