import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._();

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || !(Platform.isAndroid || Platform.isIOS)) return;
    tz.initializeTimeZones();
    final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(deviceTimeZone.identifier));
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  static Future<bool> enableDailyReminders() async {
    await initialize();
    if (!_initialized) return false;

    if (Platform.isAndroid) {
      final granted = await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      if (granted != true) return false;
    }
    if (Platform.isIOS) {
      final granted = await _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (granted != true) return false;
    }

    await _notifications.cancelAll();
    const times = [
      (hour: 9, minute: 0),
      (hour: 14, minute: 0),
      (hour: 20, minute: 0),
    ];
    for (var i = 0; i < times.length; i++) {
      await _notifications.zonedSchedule(
        id: 700 + i,
        title: 'LeetCode Daily Challenge',
        body: 'Keep your streak alive — solve today’s question.',
        scheduledDate: _nextOccurrence(times[i].hour, times[i].minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_challenge_reminders',
            'Daily challenge reminders',
            channelDescription:
                'Three reminders to solve the LeetCode daily challenge.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
    return true;
  }

  static tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
