import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum ReminderFrequency { daily, weekly, monthly }

const int reminderNotificationId = 1;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _localTimeZoneName()));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );
    await _plugin.initialize(settings: settings);
  }

  Future<String> _localTimeZoneName() async {
    // Keeping this simple: fall back to UTC if the platform lookup fails.
    try {
      return DateTime.now().timeZoneName == 'UTC' ? 'UTC' : tz.local.name;
    } catch (_) {
      return 'UTC';
    }
  }

  Future<bool> requestPermissions() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    bool granted = true;
    if (androidPlugin != null) {
      granted = await androidPlugin.requestNotificationsPermission() ?? true;
    }
    if (iosPlugin != null) {
      granted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    return granted;
  }

  tz.TZDateTime _nextInstance(int hour, int minute, ReminderFrequency freq) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduled.isBefore(now)) {
      switch (freq) {
        case ReminderFrequency.daily:
          scheduled = scheduled.add(const Duration(days: 1));
          break;
        case ReminderFrequency.weekly:
          scheduled = scheduled.add(const Duration(days: 7));
          break;
        case ReminderFrequency.monthly:
          scheduled = tz.TZDateTime(
              tz.local, now.year, now.month + 1, now.day, hour, minute);
          break;
      }
    }
    return scheduled;
  }

  Future<void> scheduleReminder({
    required int hour,
    required int minute,
    required ReminderFrequency frequency,
  }) async {
    await _plugin.cancel(id: reminderNotificationId);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'invest_reminder_channel',
        'Rappels d\'investissement',
        channelDescription: 'Rappelle d\'investir dans ton ETF',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    DateTimeComponents? matchComponents;
    switch (frequency) {
      case ReminderFrequency.daily:
        matchComponents = DateTimeComponents.time;
        break;
      case ReminderFrequency.weekly:
        matchComponents = DateTimeComponents.dayOfWeekAndTime;
        break;
      case ReminderFrequency.monthly:
        matchComponents = DateTimeComponents.dayOfMonthAndTime;
        break;
    }

    await _plugin.zonedSchedule(
      id: reminderNotificationId,
      title: 'Il est temps d\'investir 💰',
      body: 'N\'oublie pas ton versement sur ton ETF aujourd\'hui.',
      scheduledDate: _nextInstance(hour, minute, frequency),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: matchComponents,
    );
  }

  Future<void> cancelReminder() async {
    await _plugin.cancel(id: reminderNotificationId);
  }

  Future<List<PendingNotificationRequest>> pending() {
    return _plugin.pendingNotificationRequests();
  }
}
