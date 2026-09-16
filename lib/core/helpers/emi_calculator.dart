/// Re-export shim.
///
/// EMI math lives in `core/utils/emi_calculator.dart` now. This library used to
/// declare its own `EmiCalculator`, which meant the package exported two
/// different classes with the same name — importing both paths in one library
/// is an ambiguous-import compile error. The shim keeps existing
/// `core/helpers/emi_calculator.dart` imports working while there is exactly
/// one implementation. Do not add declarations here.
export 'package:enterprise_bike_showroom/core/utils/emi_calculator.dart';
