import 'package:flutter/material.dart';

import 'notification_service.dart';
import 'screens/home_screen.dart';
import 'services/portfolio_repository.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  final repository = PortfolioRepository();
  await repository.init();
  runApp(ETFReminderApp(repository: repository));
}

class ETFReminderApp extends StatefulWidget {
  final PortfolioRepository repository;
  const ETFReminderApp({super.key, required this.repository});

  @override
  State<ETFReminderApp> createState() => _ETFReminderAppState();
}

class _ETFReminderAppState extends State<ETFReminderApp> {
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_syncReminder);
    _syncReminder();
  }

  @override
  void dispose() {
    widget.repository.removeListener(_syncReminder);
    super.dispose();
  }

  Future<void> _syncReminder() async {
    final repo = widget.repository;
    if (!repo.reminderEnabled) {
      await NotificationService.instance.cancelReminder();
      return;
    }
    // Don't bail out silently if this is false: it only means the *system*
    // permission dialog was previously denied. We still (re)schedule below
    // so the reminder is ready to fire the moment the user grants it from
    // the banner on the home screen.
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.scheduleReminder(
      dayOfMonth: repo.reminderDay,
      hour: repo.reminderHour,
      minute: repo.reminderMinute,
      alreadyDoneThisMonth: repo.monthPlanComplete,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ETF Reminder',
      theme: buildAppTheme(),
      navigatorKey: notificationNavigatorKey,
      home: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) => HomeScreen(repository: widget.repository),
      ),
    );
  }
}
