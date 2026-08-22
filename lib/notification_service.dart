import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const int reminderNotificationId = 1;

// v2: bumped importance to max and renamed the channel so a stale, less
// prominent channel created by an earlier build (Android channels can't be
// reconfigured from code once created) doesn't linger on already-installed
// devices.
const _channelId = 'invest_reminder_channel_v2';

/// Navigator key shared with the app's MaterialApp, so a notification tap
/// can pop back to the home screen even if some other screen (Réglages,
/// Stats) was open when it fired.
final GlobalKey<NavigatorState> notificationNavigatorKey = GlobalKey<NavigatorState>();

/// Schedules the monthly investing reminder. It fires once on the
/// configured day of the month, then repeats every day at the same time
/// (native scheduling, works even if the app is closed) until the month's
/// plan is complete, at which point it's rescheduled for next month's day.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    final zoneName = await _localTimeZoneName();
    tz.setLocalLocation(tz.getLocation(zoneName));
    debugPrint('[NotificationService] local timezone resolved to $zoneName');

    // The status-bar/notification-tray icon must be a flat white silhouette
    // on transparent — Android strips color and draws only the alpha
    // channel, so the full-color launcher icon rendered as a blank white
    // slot there (it's opaque everywhere, alpha=1 across the whole square).
    const androidSettings = AndroidInitializationSettings('@drawable/ic_stat_notify');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[NotificationService] notification tapped: id=${response.id}');
    // Land back on the home screen regardless of which screen was open —
    // the home screen is where the month's plan and confirm button live.
    notificationNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  Future<String> _localTimeZoneName() async {
    // Ask the OS for the actual IANA zone (e.g. "Europe/Paris") — deducing
    // it from Dart alone isn't reliable (DateTime.now().timeZoneName gives
    // only an abbreviation like "CEST", not an IANA id `timezone` accepts,
    // and reading tz.local here happens before it's ever been set, so it
    // was silently resolving to UTC and shifting every scheduled time by
    // the local UTC offset — e.g. 23:49 saved as 23:49 UTC = 01:49 CEST).
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return info.identifier;
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

  /// Whether the user has actually granted the notification permission
  /// (as opposed to [requestPermissions], which only reflects what
  /// happened the moment it was called — this reads the live OS state, so
  /// it also reflects the user later revoking it from system settings).
  Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return true;
      return await androidPlugin.areNotificationsEnabled() ?? false;
    } catch (_) {
      // Platform channel not available (e.g. running in a widget test
      // without NotificationService.init()) — nothing sensible to report.
      return true;
    }
  }

  /// Next time the reminder should fire.
  ///
  /// - Done for the month already: the configured day, next month.
  /// - Not done, and the configured day/time hasn't happened yet this
  ///   month: that day, this month, as expected.
  /// - Not done, but the configured day/time already passed this month
  ///   (e.g. the reminder day was only just set up after the 1st, or the
  ///   app wasn't opened around the configured time) — the reminder is
  ///   overdue, not "for next month": anchor to the very next occurrence
  ///   of the configured time (today if it hasn't happened yet, otherwise
  ///   tomorrow) so the daily nag starts right away instead of silently
  ///   waiting a whole month.
  tz.TZDateTime nextOccurrence({
    required int dayOfMonth,
    required int hour,
    required int minute,
    required bool alreadyDoneThisMonth,
  }) {
    final now = tz.TZDateTime.now(tz.local);

    if (alreadyDoneThisMonth) {
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextMonthYear = now.month == 12 ? now.year + 1 : now.year;
      return _clampedDate(nextMonthYear, nextMonth, dayOfMonth, hour, minute);
    }

    final configuredThisMonth = _clampedDate(now.year, now.month, dayOfMonth, hour, minute);
    if (!configuredThisMonth.isBefore(now)) {
      return configuredThisMonth;
    }
    var candidate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  tz.TZDateTime _clampedDate(int year, int month, int day, int hour, int minute) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return tz.TZDateTime(tz.local, year, month, day.clamp(1, daysInMonth), hour, minute);
  }

  NotificationDetails _reminderDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Rappels d\'investissement',
          channelDescription: 'Rappelle d\'investir dans ton ETF',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );

  /// Shows a notification right away, bypassing the day/month scheduling —
  /// for checking permissions, heads-up display and tap-to-home actually
  /// work on this device, without needing to wait for the configured day.
  Future<void> showTestNotification() async {
    await _plugin.show(
      id: reminderNotificationId + 1000,
      title: 'Test du rappel ETF 💰',
      body: 'Si tu vois ceci en bannière, les notifications fonctionnent. Tape dessus pour tester le retour à l\'accueil.',
      notificationDetails: _reminderDetails(),
    );
  }

  Future<void> scheduleReminder({
    required int dayOfMonth,
    required int hour,
    required int minute,
    required bool alreadyDoneThisMonth,
  }) async {
    await _plugin.cancel(id: reminderNotificationId);

    final scheduledDate = nextOccurrence(
      dayOfMonth: dayOfMonth,
      hour: hour,
      minute: minute,
      alreadyDoneThisMonth: alreadyDoneThisMonth,
    );

    debugPrint(
      '[NotificationService] scheduling reminder id=$reminderNotificationId '
      'now=${tz.TZDateTime.now(tz.local)} target=$scheduledDate '
      'alreadyDone=$alreadyDoneThisMonth',
    );

    try {
      await _plugin.zonedSchedule(
        id: reminderNotificationId,
        title: 'Il est temps d\'investir 💰',
        body: 'Ouvre l\'appli pour voir le montant exact à virer sur ton PEA ce mois-ci.',
        scheduledDate: scheduledDate,
        notificationDetails: _reminderDetails(),
        // Inexact is plenty precise for a daily reminder banner, and avoids
        // requesting Android's exact-alarm permission (SCHEDULE_EXACT_ALARM)
        // for no real benefit — it still fires via AllowWhileIdle even in Doze.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeats daily at the same time, starting from scheduledDate —
        // this is what turns the monthly reminder into a daily nag until
        // confirmed.
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('[NotificationService] zonedSchedule call returned without throwing.');
    } catch (e) {
      debugPrint('[NotificationService] zonedSchedule threw: $e');
    }
  }

  Future<void> cancelReminder() async {
    await _plugin.cancel(id: reminderNotificationId);
  }
}
