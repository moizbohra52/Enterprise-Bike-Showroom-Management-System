import 'dart:math' as math;

import 'package:enterprise_bike_showroom/core/enums/finance_enums.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// One row of a generated EMI schedule (client-side preview).
///
/// The authoritative schedule is generated server-side by
/// `generate_emi_schedule()` using the same math; this class is used for the
/// loan-form preview and for tests.
class EmiScheduleRow {
  EmiScheduleRow({
    required this.emiNumber,
    required this.dueDate,
    required this.principalAmount,
    required this.interestAmount,
    required this.emiAmount,
  });

  final int emiNumber;
  final DateTime dueDate;
  final num principalAmount;
  final num interestAmount;
  final num emiAmount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'emi_number': emiNumber,
        'due_date': dueDate.toIso8601String(),
        'principal_amount': principalAmount,
        'interest_amount': interestAmount,
        'emi_amount': emiAmount,
      };
}

/// Pure-Dart EMI math.
///
/// Formula (reducing balance):
/// ```
/// EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
/// ```
/// where `P` = principal, `r` = monthly interest rate, `n` = months.
class EmiCalculator {
  EmiCalculator._();

  /// Monthly rate from an annual rate in percent.
  static num monthlyRate(num annualRatePercent,
      {int periodsPerYear = 12}) {
    return annualRatePercent / 100 / periodsPerYear;
  }

  /// Standard (reducing-balance) EMI amount, rounded to 2 decimals.
  static num calculateEmi(num principal, num annualRatePercent, int months) {
    if (principal <= 0 || months <= 0) return 0;
    final num r = monthlyRate(annualRatePercent);
    if (r == 0) return _round2(principal / months);
    final num factor = math.pow(1 + r, months);
    final num emi = (principal * r * factor) / (factor - 1);
    return _round2(emi);
  }

  /// Flat-rate EMI: total interest computed on the original principal.
  static num calculateEmiFlat(num principal, num annualRatePercent,
      int months) {
    if (principal <= 0 || months <= 0) return 0;
    final num totalInterest =
        principal * (annualRatePercent / 100) * (months / 12);
    return _round2((principal + totalInterest) / months);
  }

  /// EMI for the given interest type.
  static num calculate(
    num principal,
    num annualRatePercent,
    int months, {
    InterestType interestType = InterestType.reducing,
  }) {
    return interestType == InterestType.flat
        ? calculateEmiFlat(principal, annualRatePercent, months)
        : calculateEmi(principal, annualRatePercent, months);
  }

  /// Monthly EMI, named the way the sale/loan forms read it.
  ///
  /// [method] is an alias for [EmiCalculator.calculate]'s `interestType` so
  /// both flat and reducing previews share one implementation.
  static num monthlyEmi(
    num principal,
    num annualRatePercent,
    int months, {
    InterestType method = InterestType.reducing,
  }) {
    return calculate(principal, annualRatePercent, months,
        interestType: method);
  }

  /// Sum of every installment (the last one absorbs the rounding).
  static num totalEmi(
    num principal,
    num annualRatePercent,
    int months, {
    InterestType method = InterestType.reducing,
  }) {
    if (principal <= 0 || months <= 0) return _round2(principal);
    final num emi =
        monthlyEmi(principal, annualRatePercent, months, method: method);
    return _round2(emi * months);
  }

  /// One schedule row: interest, principal and the remaining balance.
  static Map<String, num> installment({
    required num principal,
    required num annualRatePercent,
    required int month,
    required int months,
    required num emi,
    required num balanceBefore,
    InterestType method = InterestType.reducing,
  }) {
    final num flatInterestPerMonth =
        principal * (annualRatePercent / 100) * (months / 12) / months;
    final num interest = method == InterestType.flat
        ? _round2(flatInterestPerMonth)
        : _round2(balanceBefore * monthlyRate(annualRatePercent));
    final num principalPart = month == months
        ? _round2(balanceBefore - interest)
        : _round2(emi - interest);
    return <String, num>{
      'interest': interest,
      'principal': principalPart,
      'balance': _round2(balanceBefore - principalPart),
    };
  }

  /// Total interest for the loan.
  static num totalInterest(
    num principal,
    num annualRatePercent,
    int months, {
    InterestType interestType = InterestType.reducing,
  }) {
    if (principal <= 0 || months <= 0) return 0;
    final num emi = calculate(principal, annualRatePercent, months,
        interestType: interestType);
    return _round2((emi * months) - principal);
  }

  /// Full amortization schedule.
  ///
  /// The final installment is adjusted so the schedule balances exactly to
  /// zero (rounding safe).
  static List<EmiScheduleRow> buildSchedule(
    num principal,
    num annualRatePercent,
    int months, {
    DateTime? startDate,
    InterestType interestType = InterestType.reducing,
  }) {
    if (principal <= 0 || months <= 0) return <EmiScheduleRow>[];

    final DateTime? firstDue = _firstDueDate(startDate);
    final List<EmiScheduleRow> rows = <EmiScheduleRow>[];

    if (interestType == InterestType.flat) {
      final num totalInterest =
          principal * (annualRatePercent / 100) * (months / 12);
      final num emi = _round2((principal + totalInterest) / months);
      final num monthlyPrincipal = _round2(principal / months);
      final num monthlyInterest = _round2(totalInterest / months);
      for (int i = 1; i <= months; i++) {
        final num principalPart = i == months
            ? _round2(principal - monthlyPrincipal * (months - 1))
            : monthlyPrincipal;
        final num interestPart = i == months
            ? _round2(totalInterest - monthlyInterest * (months - 1))
            : monthlyInterest;
        rows.add(EmiScheduleRow(
          emiNumber: i,
          dueDate: _addMonths(firstDue, i),
          principalAmount: principalPart,
          interestAmount: interestPart,
          emiAmount: _round2(principalPart + interestPart),
        ));
      }
      return rows;
    }

    final num r = monthlyRate(annualRatePercent);
    final num emi = calculateEmi(principal, annualRatePercent, months);
    num balance = principal;
    for (int i = 1; i <= months; i++) {
      num interestPart;
      num principalPart;
      if (i == months) {
        interestPart = _round2(balance * r);
        principalPart = _round2(balance);
      } else {
        interestPart = _round2(balance * r);
        principalPart = _round2(emi - interestPart);
        balance = _round2(balance - principalPart);
        if (balance < 0) balance = 0;
      }
      rows.add(EmiScheduleRow(
        emiNumber: i,
        dueDate: _addMonths(firstDue, i),
        principalAmount: principalPart,
        interestAmount: interestPart,
        emiAmount: _round2(principalPart + interestPart),
      ));
    }
    return rows;
  }

  static DateTime? _firstDueDate(DateTime? startDate) {
    if (startDate == null) return DateTime(2000, 1, 1);
    return DateTime(startDate.year, startDate.month, startDate.day);
  }

  static DateTime _addMonths(DateTime? base, int months) {
    final DateTime b = base ?? DateTime(2000, 1, 1);
    final int totalMonths = b.year * 12 + (b.month - 1) + months;
    final int year = (totalMonths / 12).floor();
    final int month = (totalMonths % 12) + 1;
    final int daysInMonth =
        DateTime(year, month + 1, 0).day;
    final int day = b.day > daysInMonth ? daysInMonth : b.day;
    return DateTime(year, month, day);
  }

  static num _round2(num value) => (value * 100).roundToDouble() / 100;
}

/// Helpers to summarize an EMI schedule from wire rows.
class EmiScheduleSummary {
  EmiScheduleSummary({
    required this.totalEmi,
    required this.paidAmount,
    required this.remainingAmount,
    required this.dueCount,
    required this.overdueCount,
  });

  final num totalEmi;
  final num paidAmount;
  final num remainingAmount;
  final int dueCount;
  final int overdueCount;

  factory EmiScheduleSummary.fromRows(List<Map<String, dynamic>> rows) {
    num total = 0;
    num paid = 0;
    int due = 0;
    int overdue = 0;
    for (final Map<String, dynamic> row in rows) {
      total += SafeJson.asMoney(row['emi_amount']);
      paid += SafeJson.asMoney(row['paid_amount']);
      final String status = SafeJson.asText(row['status']);
      if (status == 'due') due++;
      if (status == 'overdue') overdue++;
    }
    return EmiScheduleSummary(
      totalEmi: EmiCalculator._round2(total),
      paidAmount: EmiCalculator._round2(paid),
      remainingAmount: EmiCalculator._round2(total - paid),
      dueCount: due,
      overdueCount: overdue,
    );
  }
}
