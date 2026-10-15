import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// First id of the reminder series — see [NotificationService.scheduleReminder].
/// Starts at 1 so the single daily-repeating reminder armed by older builds
/// (which used id 1) gets cancelled along with the rest of the series.
const int reminderNotificationId = 1;

/// How many consecutive daily reminders are armed ahead of time. Each one
/// is a plain one-shot alarm, so the nag keeps going for this many days
/// even if the app is never opened; every app open/resume re-arms a fresh
/// series anyway, so this only needs to outlast a long stretch of ignoring
/// it.
const int reminderSeriesLength = 62;

// v2: bumped importance to max and renamed the channel so a stale, less
// prominent channel created by an earlier build (Android channels can't be
// reconfigured from code once created) doesn't linger on already-installed
// devices.
const _channelId = 'invest_reminder_channel_v2';

/// Navigator key shared with the app's MaterialApp, so a notification tap
/// can pop back to the home screen even if some other screen (a dialog, a
/// bottom sheet) was open when it fired.
final GlobalKey<NavigatorState> notificationNavigatorKey =
    GlobalKey<NavigatorState>();

/// Schedules the monthly investing reminder. It fires on the configured day
/// of the month, then again every day at the same time (native scheduling,
/// works even if the app is closed) until the month's plan is complete, at
/// which point it's rescheduled for next month's day.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set by [HomeScreen] once mounted, so a notification tap can also reset
  /// the swipeable home screen back to its main page — Stats/Réglages are
  /// pages of the same route now, not separate ones `notificationNavigatorKey`
  /// could pop back from.
  VoidCallback? onNotificationTappedResetHome;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    final zoneName = await _localTimeZoneName();
    tz.setLocalLocation(tz.getLocation(zoneName));
    debugPrint('[NotificationService] local timezone resolved to $zoneName');

    // The status-bar/notification-tray icon must be a flat white silhouette
    // on transparent — Android strips color and draws only the alpha
    // channel, so the full-color launcher icon rendered as a blank white
    // slot there (it's opaque everywhere, alpha=1 across the whole square).
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_stat_notify',
    );
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
    // Land back on the home page regardless of which page/screen was open —
    // that's where the month's plan and confirm button live.
    notificationNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    onNotificationTappedResetHome?.call();
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
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    bool granted = true;
    if (androidPlugin != null) {
      granted = await androidPlugin.requestNotificationsPermission() ?? true;
    }
    if (iosPlugin != null) {
      granted =
          await iosPlugin.requestPermissions(
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
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
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

    final configuredThisMonth = _clampedDate(
      now.year,
      now.month,
      dayOfMonth,
      hour,
      minute,
    );

    if (alreadyDoneThisMonth) {
      // This month's occurrence might still be ahead of us — e.g. the app
      // re-syncs mid-period (day 3, reminder day 10) for a period that was
      // already satisfied back on day 25 of the *previous* cycle: the next
      // occurrence is still this month's day 10, not a whole extra month
      // away. Only actually skip to next month once this month's own
      // occurrence has already passed.
      if (!configuredThisMonth.isBefore(now)) {
        return configuredThisMonth;
      }
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextMonthYear = now.month == 12 ? now.year + 1 : now.year;
      return _clampedDate(nextMonthYear, nextMonth, dayOfMonth, hour, minute);
    }

    if (!configuredThisMonth.isBefore(now)) {
      return configuredThisMonth;
    }
    var candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// The [count] consecutive daily occurrences of [first]'s time of day,
  /// starting at [first] itself. Built from calendar fields rather than by
  /// adding 24h durations, so the wall-clock time stays put across DST
  /// changes.
  List<tz.TZDateTime> dailySeries(tz.TZDateTime first, int count) => [
    for (var i = 0; i < count; i++)
      tz.TZDateTime(
        tz.local,
        first.year,
        first.month,
        first.day + i,
        first.hour,
        first.minute,
      ),
  ];

  tz.TZDateTime _clampedDate(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return tz.TZDateTime(
      tz.local,
      year,
      month,
      day.clamp(1, daysInMonth),
      hour,
      minute,
    );
  }

  NotificationDetails _reminderDetails({Duration? timeout}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Rappels d\'investissement',
          channelDescription: 'Rappelle d\'investir dans ton ETF',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          timeoutAfter: timeout?.inMilliseconds,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      );

  /// Shows a notification right away, bypassing the day/month scheduling —
  /// for checking permissions, heads-up display and tap-to-home actually
  /// work on this device, without needing to wait for the configured day.
  Future<void> showTestNotification() async {
    await _plugin.show(
      id: reminderNotificationId + 1000,
      title: 'Test du rappel ETF 💰',
      body:
          'Si tu vois ceci en bannière, les notifications fonctionnent. Tape dessus pour tester le retour à l\'accueil.',
      notificationDetails: _reminderDetails(),
    );
  }

  /// Serializes [scheduleReminder]/[cancelReminder]: they're triggered on
  /// every repository change and app resume, and two interleaved runs could
  /// otherwise leave a mix of both series armed.
  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() task) =>
      _queue = _queue.then((_) => task()).catchError((Object e) {
        debugPrint('[NotificationService] reminder sync failed: $e');
      });

  Future<void> scheduleReminder({
    required int dayOfMonth,
    required int hour,
    required int minute,
    required bool alreadyDoneThisMonth,
  }) => _enqueue(() async {
    await _cancelSeries();

    final first = nextOccurrence(
      dayOfMonth: dayOfMonth,
      hour: hour,
      minute: minute,
      alreadyDoneThisMonth: alreadyDoneThisMonth,
    );

    debugPrint(
      '[NotificationService] scheduling $reminderSeriesLength daily reminders '
      'now=${tz.TZDateTime.now(tz.local)} first=$first '
      'alreadyDone=$alreadyDoneThisMonth',
    );

    // One plain one-shot alarm per day rather than a single daily-repeating
    // one: flutter_local_notifications' matchDateTimeComponents throws away
    // the requested date and re-anchors to "today/tomorrow" (confirmed via
    // `adb shell dumpsys alarm`), so it can't start a repeat at a future
    // date — and a lone one-shot on the reminder day only ever fired once:
    // swiping it away left nothing armed for the next day unless the app
    // happened to be opened in between.
    final series = dailySeries(first, reminderSeriesLength);
    for (var i = 0; i < series.length; i++) {
      await _plugin.zonedSchedule(
        id: reminderNotificationId + i,
        title: 'Il est temps d\'investir 💰',
        body:
            'Ouvre l\'appli pour voir le montant exact à virer sur ton PEA ce mois-ci.',
        scheduledDate: series[i],
        // Each day's reminder clears itself just before the next one shows
        // up, so ignored reminders don't pile up in the tray.
        notificationDetails: _reminderDetails(
          timeout: const Duration(hours: 23, minutes: 50),
        ),
        // Inexact is plenty precise for a daily reminder banner, and avoids
        // requesting Android's exact-alarm permission (SCHEDULE_EXACT_ALARM)
        // for no real benefit — it still fires via AllowWhileIdle even in Doze.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  });

  Future<void> cancelReminder() => _enqueue(_cancelSeries);

  Future<void> _cancelSeries() async {
    for (var i = 0; i < reminderSeriesLength; i++) {
      await _plugin.cancel(id: reminderNotificationId + i);
    }
  }
}
