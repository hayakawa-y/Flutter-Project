// lib/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  static bool _inited = false;
  static bool _tzInited = false;

  /// ✅ 初始化时区（zonedSchedule 必须）
  static Future<void> _initTimeZone() async {
    if (_tzInited) return;
    tzdata.initializeTimeZones();

    // 你在泰国：先固定 Bangkok，保证能稳定触发
    // 如果你之后要自动识别设备时区，再加 flutter_native_timezone 等插件来动态设置。
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

    _tzInited = true;
  }

  /// ✅ 初始化通知（main.dart 里调用一次）
  static Future<void> init() async {
    if (_inited) return;

    await _initTimeZone();

    // Android 初始化
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS 初始化
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    // ✅ Android 13+ 通知权限
    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _inited = true;
  }

  /// ✅ 取消多个通知（编辑/删除时用）
  static Future<void> cancelMany(List<int> ids) async {
    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }

  /// ✅ 安排一次通知（本地时间）——使用 zonedSchedule（新版本不再用 schedule）
  static Future<void> scheduleOnce({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    if (!when.isAfter(now)) return;

    const androidDetails = AndroidNotificationDetails(
      'med_reminder_channel',
      'Medication Reminders',
      channelDescription: 'Medication reminder notifications',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    final details =
    const NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      details,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // 下面这个参数在部分版本是必需的；如果你这行报错，我再按你版本改成兼容写法
      matchDateTimeComponents: null,
    );
  }

  /// ✅ 用药提醒：从 startDate 到 endDate，每天多个时间点安排通知
  static Future<List<int>> scheduleMedication({
    required int baseId,
    required String title,
    required String body,
    required DateTime startDate,
    required DateTime endDate,
    required List<DateTime> timesInDay,
  }) async {
    final out = <int>[];

    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    int seq = 0;

    for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      for (final t in timesInDay) {
        final when = DateTime(d.year, d.month, d.day, t.hour, t.minute);

        // 只安排未来的
        if (!when.isAfter(DateTime.now())) {
          seq++;
          continue;
        }

        final id = baseId + seq; // 保证唯一
        seq++;

        await scheduleOnce(
          id: id,
          when: when,
          title: title,
          body: body,
        );

        out.add(id);
      }
    }

    return out;
  }
}