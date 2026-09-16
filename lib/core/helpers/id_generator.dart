/// Re-export shim.
///
/// Id generation lives in `core/utils/id_generator.dart` now. This library used
/// to declare a second `IdGenerator`, so the package exported two classes with
/// the same name — importing both paths in one library is an ambiguous-import
/// compile error. The shim keeps existing `core/helpers/id_generator.dart`
/// imports working while there is exactly one implementation. Do not add
/// declarations here.
export 'package:enterprise_bike_showroom/core/utils/id_generator.dart';
