import 'package:flutter/material.dart';

import 'notification_service.dart';
import 'screens/home_screen.dart';
import 'services/allocation_calculator.dart';
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
    final granted = await NotificationService.instance.requestPermissions();
    if (!granted) return;
    await NotificationService.instance.scheduleReminder(
      dayOfMonth: repo.reminderDay,
      hour: repo.reminderHour,
      minute: repo.reminderMinute,
      alreadyDoneThisMonth: _monthPlanComplete(repo),
    );
  }

  /// True once there's nothing left to sensibly recommend this month —
  /// either the remaining budget can't cover another minimum order, or the
  /// portfolio has already reached its target allocation.
  bool _monthPlanComplete(PortfolioRepository repo) {
    if (repo.etfs.isEmpty) return true;
    if (repo.budgetLeftThisMonth < repo.minOrderAmount) return true;
    try {
      final plan = AllocationCalculator().computeMonthlyPlan(
        holdings: repo.holdings,
        availableBudget: repo.budgetLeftThisMonth,
        minOrderAmount: repo.minOrderAmount,
        commissionRatePct: repo.commissionRatePct,
      );
      return plan.purchases.isEmpty;
    } on AllocationError {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ETF Reminder',
      theme: buildAppTheme(),
      home: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) => HomeScreen(repository: widget.repository),
      ),
    );
  }
}
