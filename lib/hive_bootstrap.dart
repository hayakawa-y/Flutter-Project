import 'package:hive_flutter/hive_flutter.dart';

class HiveBootstrap {
  static Future<void> init() async {
    await Hive.initFlutter();

    await Hive.openBox('health_records');
    await Hive.openBox('medications');
    await Hive.openBox('users');
    await Hive.openBox('session');
  }
}