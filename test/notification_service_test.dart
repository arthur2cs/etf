import 'package:etf_reminder/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Paris'));
  });

  final service = NotificationService.instance;

  test('reminder day still upcoming this month: anchors to that day', () {
    final now = tz.TZDateTime.now(tz.local);
    // A day comfortably after today, so it's still upcoming.
    final upcomingDay = now.day < 27 ? now.day + 1 : 1;

    final next = service.nextOccurrence(
      dayOfMonth: upcomingDay,
      hour: 9,
      minute: 0,
      alreadyDoneThisMonth: false,
    );

    expect(next.isAfter(now), isTrue);
    expect(next.month, upcomingDay > now.day ? now.month : (now.month == 12 ? 1 : now.month + 1));
  });

  test('reminder day already passed this month and nothing done: does NOT jump to next '
      'month — anchors to the next occurrence of the configured time instead', () {
    final now = tz.TZDateTime.now(tz.local);
    // Day 1 has necessarily already passed unless it literally is the 1st.
    if (now.day == 1) return; // not a meaningful case to simulate today

    final next = service.nextOccurrence(
      dayOfMonth: 1,
      hour: now.hour,
      minute: now.minute + 5 > 59 ? now.minute : now.minute + 5,
      alreadyDoneThisMonth: false,
    );

    // Must stay within a day of "now", never jump a whole month ahead.
    expect(next.difference(now).inHours, lessThan(25));
  });

  test('reminder already done this month: anchors to the configured day next month', () {
    final now = tz.TZDateTime.now(tz.local);

    final next = service.nextOccurrence(
      dayOfMonth: now.day,
      hour: now.hour,
      minute: now.minute,
      alreadyDoneThisMonth: true,
    );

    final expectedMonth = now.month == 12 ? 1 : now.month + 1;
    expect(next.month, expectedMonth);
    expect(next.isAfter(now), isTrue);
  });
}
