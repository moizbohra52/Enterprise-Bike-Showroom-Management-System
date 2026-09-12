import 'package:flutter/material.dart';

import 'package:enterprise_bike_showroom/app.dart';
import 'package:enterprise_bike_showroom/routes/app_bootstrap.dart';

/// Application entry point.
///
/// Boots infrastructure (preferences, Hive, Supabase, Firebase), registers the
/// global service/controller graph (see [AppBootstrap]) and only then runs the
/// app, so that every screen can safely `Get.find<T>()` what it needs.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBootstrap.init();
  runApp(const EnterpriseBikeApp());
}
