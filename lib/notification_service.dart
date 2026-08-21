import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const int reminderNotificationId = 1;

/// Schedules the monthly investing reminder. It fires once on the
/// configured day of the month, then repeats every day at the same time
/// (native scheduling, works even if the app is closed) until [confirm] is
/// called, at which point it's rescheduled for next month's day.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _localTimeZoneName()));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

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

  /// Next time the reminder should fire: the configured day of this month,
  /// unless it has already passed or this month's investment is already
  /// done — in which case, that day next month.
  tz.TZDateTime _nextOccurrence({
    required int dayOfMonth,
    required int hour,
    required int minute,
    required bool alreadyDoneThisMonth,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = _clampedDate(now.year, now.month, dayOfMonth, hour, minute);

    if (alreadyDoneThisMonth || candidate.isBefore(now)) {
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextMonthYear = now.month == 12 ? now.year + 1 : now.year;
      candidate = _clampedDate(nextMonthYear, nextMonth, dayOfMonth, hour, minute);
    }
    return candidate;
  }

  tz.TZDateTime _clampedDate(int year, int month, int day, int hour, int minute) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return tz.TZDateTime(tz.local, year, month, day.clamp(1, daysInMonth), hour, minute);
  }

  Future<void> scheduleReminder({
    required int dayOfMonth,
    required int hour,
    required int minute,
    required bool alreadyDoneThisMonth,
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

    await _plugin.zonedSchedule(
      id: reminderNotificationId,
      title: 'Il est temps d\'investir 💰',
      body: 'Ouvre l\'appli pour voir le montant exact à virer sur ton PEA ce mois-ci.',
      scheduledDate: _nextOccurrence(
        dayOfMonth: dayOfMonth,
        hour: hour,
        minute: minute,
        alreadyDoneThisMonth: alreadyDoneThisMonth,
      ),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats daily at the same time, starting from scheduledDate — this
      // is what turns the monthly reminder into a daily nag until confirmed.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelReminder() async {
    await _plugin.cancel(id: reminderNotificationId);
  }

  Future<List<PendingNotificationRequest>> pending() {
    return _plugin.pendingNotificationRequests();
  }
}
