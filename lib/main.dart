import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notification_service.dart';
import 'screens/home_screen.dart';
import 'services/portfolio_repository.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15+ enforces edge-to-edge — app content can draw (and while
  // scrolling, does draw) underneath the system nav bar's button/gesture
  // area, and systemNavigationBarColor is deprecated there and simply
  // ignored. So instead of asking the OS to paint that strip, MaterialApp's
  // builder below paints an opaque bar over it directly: scrolled content
  // now disappears behind that bar rather than showing through it.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
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

class _ETFReminderAppState extends State<ETFReminderApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(_syncReminder);
    _syncReminder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.removeListener(_syncReminder);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-affirm the schedule on every foreground, not just on a cold
    // start: the app process can survive in the background for days
    // without ever rebuilding this widget, so without this, reopening it
    // from the app switcher wouldn't re-check whether the plan is still
    // complete unless some unrelated repo mutation happened to fire
    // notifyListeners in between.
    if (state == AppLifecycleState.resumed) _syncReminder();
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
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: notificationNavigatorKey,
      // Pins an opaque bar over the system nav bar's button/gesture area on
      // every screen, so scrolled content disappears behind it instead of
      // showing through — see the comment on setEnabledSystemUIMode above.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).viewPadding.bottom,
            child: const IgnorePointer(child: ColoredBox(color: Colors.black)),
          ),
        ],
      ),
      home: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) => HomeScreen(repository: widget.repository),
      ),
    );
  }
}
