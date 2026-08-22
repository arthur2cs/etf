import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/investment_transaction.dart';
import '../notification_service.dart';
import '../services/allocation_calculator.dart';
import '../services/portfolio_repository.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

final _eur = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
final _dateFmt = DateFormat('dd/MM/yyyy');

const _palette = AppColors.chartPalette;

class HomeScreen extends StatefulWidget {
  final PortfolioRepository repository;
  const HomeScreen({super.key, required this.repository});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _notificationIssue = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNotificationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNotificationStatus();
  }

  Future<void> _checkNotificationStatus() async {
    if (!widget.repository.reminderEnabled) {
      if (mounted) setState(() => _notificationIssue = false);
      return;
    }
    final notifsOk = await NotificationService.instance.areNotificationsEnabled();
    if (!mounted) return;
    setState(() => _notificationIssue = !notifsOk);
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/icon/renard_icon.png', width: 36, height: 36),
            ),
            const SizedBox(width: 10),
            const Text('Suivi PEA'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Stats',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StatsScreen(repository: repo)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Réglages',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(repository: repo)),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await repo.syncFromSheets();
          await repo.refreshPrices();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_notificationIssue) _NotificationWarningCard(repo: repo),
            if (!repo.isSignedIn) _SignInCard(repo: repo),
            if (repo.lastError != null) _ErrorCard(message: repo.lastError!),
            if (repo.etfs.isNotEmpty) _PieChartCard(repo: repo),
            const SizedBox(height: 16),
            _MonthlyPlanCard(repo: repo),
          ],
        ),
      ),
    );
  }
}

class _SignInCard extends StatelessWidget {
  final PortfolioRepository repo;
  const _SignInCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Connecte ton compte Google pour synchroniser tes données avec Google Sheets.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await repo.signIn();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Connexion impossible : $e')));
                  }
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Se connecter avec Google'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationWarningCard extends StatelessWidget {
  final PortfolioRepository repo;
  const _NotificationWarningCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Le rappel mensuel n\'est pas fiable en l\'état (notifications désactivées) — '
              'corrige ça dans les réglages sinon tu risques de ne rien recevoir.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Ouvrir les réglages'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsScreen(repository: repo)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}

class _PieChartCard extends StatelessWidget {
  final PortfolioRepository repo;
  const _PieChartCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final holdings = repo.holdings.where((h) => h.investedEur > 0).toList();
    final total = repo.totalInvested;

    if (holdings.isEmpty || total <= 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aucun investissement enregistré pour le moment.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Capital investi : ${_eur.format(total)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: [
                    for (var i = 0; i < holdings.length; i++)
                      PieChartSectionData(
                        value: holdings[i].investedEur,
                        color: _palette[i % _palette.length],
                        title: '${(holdings[i].investedEur / total * 100).toStringAsFixed(0)}%',
                        radius: 70,
                        titleStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.labelColorOn(_palette[i % _palette.length]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < holdings.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _palette[i % _palette.length],
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(holdings[i].etf.name)),
                    Text(_eur.format(holdings[i].investedEur)),
                    const SizedBox(width: 8),
                    Text(
                      'cible ${holdings[i].etf.targetPct.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyPlanCard extends StatelessWidget {
  final PortfolioRepository repo;
  const _MonthlyPlanCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    if (repo.etfs.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Ajoute au moins un ETF dans les réglages pour démarrer.'),
        ),
      );
    }

    final now = DateTime.now();
    final txThisMonth = repo.transactionsInMonth(now)..sort((a, b) => a.date.compareTo(b.date));

    MonthlyPlan plan;
    try {
      plan = AllocationCalculator().computeMonthlyPlan(
        holdings: repo.holdings,
        availableBudget: repo.budgetLeftThisMonth,
        minOrderAmount: repo.minOrderAmount,
        commissionRatePct: repo.commissionRatePct,
      );
    } catch (e) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$e'),
        ),
      );
    }

    if (plan.purchases.isEmpty) {
      if (txThisMonth.isEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              repo.budgetLeftThisMonth < repo.minOrderAmount
                  ? 'Budget mensuel (${_eur.format(repo.monthlyBudget)}) inférieur au minimum '
                      'd\'ordre (${_eur.format(repo.minOrderAmount)}) : augmente-le dans les réglages.'
                  : 'Portefeuille déjà à l\'équilibre par rapport à ta répartition cible — '
                      'rien à investir de plus ce mois-ci.',
            ),
          ),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ce mois-ci ✅', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final t in txThisMonth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Investi le ${_dateFmt.format(t.date)} : ${_eur.format(t.netAmountEur)} '
                    '(dont ${_eur.format(t.commissionEur)} de commission) sur ${t.isin}',
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              txThisMonth.isEmpty ? 'Ce mois-ci' : 'Ce mois-ci — encore à faire',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final t in txThisMonth)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '✅ Déjà investi le ${_dateFmt.format(t.date)} : ${_eur.format(t.netAmountEur)} sur ${t.isin}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Text(
              'Vire ${_eur.format(plan.totalToTransfer)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            for (final purchase in plan.purchases)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Achète ${purchase.shares} action(s) de ${purchase.etf.name} pour '
                  '${_eur.format(purchase.amountEur)} (+ ${_eur.format(purchase.commissionEur)} de '
                  'commission, prix unitaire ${_eur.format(purchase.unitPrice)}).',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            if (plan.unallocatedEur >= 1)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '${_eur.format(plan.unallocatedEur)} restent non alloués ce mois-ci '
                  '(insuffisant pour un ordre supplémentaire).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(plan.purchases.length > 1 ? "J'ai fait les transactions" : "J'ai fait la transaction"),
              onPressed: () => _confirmTransactions(context, repo, plan.purchases),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTransactions(
    BuildContext context,
    PortfolioRepository repo,
    List<PlannedPurchase> purchases,
  ) async {
    final amountControllers = [
      for (final p in purchases) TextEditingController(text: p.amountEur.toStringAsFixed(2)),
    ];
    final sharesControllers = [
      for (final p in purchases) TextEditingController(text: p.shares.toString()),
    ];
    final priceControllers = [
      for (final p in purchases) TextEditingController(text: p.unitPrice.toStringAsFixed(2)),
    ];
    final commissionControllers = [
      for (final p in purchases) TextEditingController(text: p.commissionEur.toStringAsFixed(2)),
    ];
    DateTime date = DateTime.now();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    purchases.length > 1 ? 'Confirmer les transactions' : 'Confirmer la transaction',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Date : ${_dateFmt.format(date)}'),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
                  ),
                  for (var i = 0; i < purchases.length; i++) ...[
                    const Divider(height: 24),
                    Text(purchases[i].etf.name, style: Theme.of(context).textTheme.titleSmall),
                    TextField(
                      controller: amountControllers[i],
                      decoration: const InputDecoration(labelText: 'Montant (€)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    TextField(
                      controller: sharesControllers[i],
                      decoration: const InputDecoration(labelText: "Nombre d'actions"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    TextField(
                      controller: priceControllers[i],
                      decoration: const InputDecoration(labelText: 'Prix unitaire (€)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    TextField(
                      controller: commissionControllers[i],
                      decoration: const InputDecoration(labelText: 'Commission (€)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      for (var i = 0; i < purchases.length; i++) {
        final purchase = purchases[i];
        final amount =
            double.tryParse(amountControllers[i].text.replaceAll(',', '.')) ?? purchase.amountEur;
        final shares = double.tryParse(sharesControllers[i].text.replaceAll(',', '.')) ??
            purchase.shares.toDouble();
        final price =
            double.tryParse(priceControllers[i].text.replaceAll(',', '.')) ?? purchase.unitPrice;
        final commission = double.tryParse(commissionControllers[i].text.replaceAll(',', '.')) ??
            purchase.commissionEur;
        await repo.addTransaction(InvestmentTransaction(
          date: date,
          isin: purchase.etf.isin,
          amountEur: amount,
          unitPrice: price,
          shares: shares,
          commissionEur: commission,
        ));
      }
    }
  }
}
