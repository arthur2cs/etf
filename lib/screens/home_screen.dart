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

const _pageTitles = ['Stats & projections', 'Suivi PEA', 'Réglages'];
const _pageIcons = [Icons.bar_chart, Icons.home, Icons.settings];

/// Stock [PageView] physics need a drag past 50% of the page (absent a
/// real flick) before committing to the next page, and settle with a
/// fairly soft spring — noticeably less responsive than apps like Snapchat,
/// which commit after a much shorter drag and settle quickly. Same overall
/// algorithm as [PageScrollPhysics], just with a lower commit threshold and
/// a stiffer settle spring.
class _SnappyPageScrollPhysics extends ScrollPhysics {
  const _SnappyPageScrollPhysics({super.parent});

  @override
  _SnappyPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnappyPageScrollPhysics(parent: buildParent(ancestor));

  // vs. stock PageView's implicit 0.5 (must drag past the halfway point).
  static const _commitFraction = 0.2;

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 400, ratio: 1.1);

  double _page(ScrollMetrics position) =>
      position.pixels / position.viewportDimension;

  double _pixelsForPage(ScrollMetrics position, double page) =>
      page * position.viewportDimension;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final page = _page(position);
    double targetPage;
    if (velocity.abs() > tolerance.velocity) {
      // A real flick always commits fully in its direction, same as stock.
      targetPage = (page + (velocity > 0 ? 0.5 : -0.5)).roundToDouble();
    } else {
      // No meaningful flick: commit once the drag clears _commitFraction of
      // the page instead of stock's 50%, otherwise snap back to where the
      // drag started.
      final nearest = page.roundToDouble();
      final offset = page - nearest;
      targetPage = offset.abs() > _commitFraction
          ? nearest + offset.sign
          : nearest;
    }
    final target = _pixelsForPage(position, targetPage);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}

/// Root screen: a 3-page swipeable carousel (Stats ⇄ Home ⇄ Réglages)
/// behind a single shared AppBar, instead of Home pushing separate routes
/// for Stats/Réglages. Home stays the initial/center page (index 1).
class HomeScreen extends StatefulWidget {
  final PortfolioRepository repository;
  const HomeScreen({super.key, required this.repository});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late final PageController _pageController;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    // So a notification tap can bring the app back to the main page even
    // if the user had swiped over to Stats/Réglages in the meantime.
    NotificationService.instance.onNotificationTappedResetHome = () =>
        _jumpTo(1);
  }

  @override
  void dispose() {
    NotificationService.instance.onNotificationTappedResetHome = null;
    _pageController.dispose();
    super.dispose();
  }

  void _jumpTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    return PopScope(
      // A single route now backs all 3 pages, so a system back from
      // Stats/Réglages would otherwise exit the app outright — go back to
      // the main page first instead, like a normal bottom-nav app would.
      canPop: _currentPage == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _jumpTo(1);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/icon/renard.png',
                  width: 36,
                  height: 36,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _pageTitles[_currentPage],
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // No extra horizontal padding around each icon: IconButton already
          // reserves its own ~48px tap target, and every pixel here narrows
          // the room left for the title text next to it.
          actions: [
            for (var i = 0; i < 3; i++)
              i == _currentPage
                  ? IconButton.filled(
                      icon: Icon(_pageIcons[i]),
                      onPressed: () => _jumpTo(i),
                    )
                  : IconButton(
                      icon: Icon(_pageIcons[i]),
                      onPressed: () => _jumpTo(i),
                    ),
            const SizedBox(width: 4),
          ],
        ),
        body: PageView(
          controller: _pageController,
          // pageSnapping stays true by default only lets PageView wrap a
          // *stock* PageScrollPhysics around whatever `physics` is set to —
          // with its own hardcoded 50% commit threshold, taking over the
          // snap decision entirely regardless of what we pass in. Disabling
          // it here is what actually lets _SnappyPageScrollPhysics decide.
          pageSnapping: false,
          physics: const _SnappyPageScrollPhysics(),
          onPageChanged: (i) => setState(() => _currentPage = i),
          children: [
            StatsScreen(repository: repo),
            _HomeBody(repository: repo, onOpenSettings: () => _jumpTo(2)),
            SettingsScreen(repository: repo),
          ],
        ),
      ),
    );
  }
}

class _HomeBody extends StatefulWidget {
  final PortfolioRepository repository;
  final VoidCallback onOpenSettings;
  const _HomeBody({required this.repository, required this.onOpenSettings});

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> with WidgetsBindingObserver {
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
    final notifsOk = await NotificationService.instance
        .areNotificationsEnabled();
    if (!mounted) return;
    setState(() => _notificationIssue = !notifsOk);
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    return RefreshIndicator(
      onRefresh: () async {
        await repo.syncFromSheets();
        await repo.refreshPrices();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding(context)),
        children: [
          if (_notificationIssue)
            _NotificationWarningCard(onOpenSettings: widget.onOpenSettings),
          if (!repo.isSignedIn) _SignInCard(repo: repo),
          if (repo.lastError != null) _ErrorCard(message: repo.lastError!),
          if (repo.etfs.isNotEmpty) _PieChartCard(repo: repo),
          const SizedBox(height: 16),
          _MonthlyPlanCard(repo: repo),
        ],
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
            const Text(
              'Connecte ton compte Google pour synchroniser tes données avec Google Sheets.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await repo.signIn();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Connexion impossible : $e')),
                    );
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
  final VoidCallback onOpenSettings;
  const _NotificationWarningCard({required this.onOpenSettings});

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
              onPressed: onOpenSettings,
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
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
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
            Text(
              'Capital investi : ${_eur.format(total)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
                        title:
                            '${(holdings[i].investedEur / total * 100).toStringAsFixed(0)}%',
                        radius: 70,
                        titleStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.labelColorOn(
                            _palette[i % _palette.length],
                          ),
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

/// One ETF's order in the monthly plan: the ETF name, then how many shares
/// at what price, then the total with its commission — set off by an accent
/// bar rather than run together into a sentence.
class _PurchaseSection extends StatelessWidget {
  final PlannedPurchase purchase;
  final Color color;
  const _PurchaseSection({required this.purchase, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final shares = purchase.shares;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            purchase.etf.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$shares action${shares > 1 ? 's' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' à ${_eur.format(purchase.unitPrice)}'),
              ],
            ),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Total '),
                TextSpan(
                  text: _eur.format(purchase.amountEur),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text:
                      '  (+ ${_eur.format(purchase.commissionEur)} de commission)',
                  style: muted,
                ),
              ],
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ],
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
          child: Text(
            'Ajoute au moins un ETF dans les réglages pour démarrer.',
          ),
        ),
      );
    }

    final txThisMonth = repo.transactionsInCurrentPeriod
      ..sort((a, b) => a.date.compareTo(b.date));

    // A transaction recorded this period means the period's done — the
    // recommended purchase is already optimized for the budget, so
    // whatever was actually validated (edited amount included) counts,
    // regardless of whether it exactly matches the plan computed below.
    if (txThisMonth.isNotEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ce mois-ci ✅',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
        child: Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
      );
    }

    if (plan.purchases.isEmpty) {
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
            Text('Ce mois-ci', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Vire ${_eur.format(plan.totalToTransfer)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 4),
            for (final purchase in plan.purchases)
              _PurchaseSection(
                purchase: purchase,
                // Same color as this ETF's slice in the pie chart above.
                color:
                    _palette[repo.etfs.indexWhere(
                          (e) => e.isin == purchase.etf.isin,
                        ) %
                        _palette.length],
              ),
            if (plan.unallocatedEur >= 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${_eur.format(plan.unallocatedEur)} restent non alloués ce mois-ci '
                  '(insuffisant pour un ordre supplémentaire).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(
                plan.purchases.length > 1
                    ? "J'ai fait les transactions"
                    : "J'ai fait la transaction",
              ),
              onPressed: () =>
                  _confirmTransactions(context, repo, plan.purchases),
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
    final transactions =
        await showModalBottomSheet<List<InvestmentTransaction>>(
          context: context,
          isScrollControlled: true,
          // Defaults to false, which — per its own doc comment — actively
          // strips top padding via MediaQuery.removePadding so a SafeArea
          // *inside* the sheet has no effect at the top edge. That's exactly
          // why wrapping the content in our own SafeArea didn't stop the
          // title from sitting under the status bar with several ETFs (sheet
          // tall enough to reach the top): the framework needs to be told to
          // keep the sheet itself clear of the top/left/right system
          // intrusions, not just padded internally.
          useSafeArea: true,
          builder: (context) => _ConfirmTransactionsSheet(
            purchases: purchases,
            commissionRatePct: repo.commissionRatePct,
          ),
        );
    if (transactions == null) return;
    for (final transaction in transactions) {
      await repo.addTransaction(transaction);
    }
  }
}

/// Bottom sheet for confirming (and correcting) the month's purchases.
/// Pops with the transactions to record, or null if dismissed.
///
/// Owns its controllers and focus nodes so they're disposed only once the
/// sheet is actually unmounted — disposing them as soon as
/// showModalBottomSheet's future completed tore them down while the sheet
/// was still on screen animating out, with its TextFields still attached,
/// which tripped the framework's `_dependents.isEmpty` assertion.
class _ConfirmTransactionsSheet extends StatefulWidget {
  final List<PlannedPurchase> purchases;
  final double commissionRatePct;

  const _ConfirmTransactionsSheet({
    required this.purchases,
    required this.commissionRatePct,
  });

  @override
  State<_ConfirmTransactionsSheet> createState() =>
      _ConfirmTransactionsSheetState();
}

class _ConfirmTransactionsSheetState extends State<_ConfirmTransactionsSheet> {
  late final List<PlannedPurchase> purchases = widget.purchases;
  late final amountControllers = [
    for (final p in purchases)
      TextEditingController(text: p.amountEur.toStringAsFixed(2)),
  ];
  late final sharesControllers = [
    for (final p in purchases) TextEditingController(text: p.shares.toString()),
  ];
  late final priceControllers = [
    for (final p in purchases)
      TextEditingController(text: p.unitPrice.toStringAsFixed(2)),
  ];
  late final commissionControllers = [
    for (final p in purchases)
      TextEditingController(text: p.commissionEur.toStringAsFixed(2)),
  ];
  late final priceFocusNodes = [for (final _ in purchases) FocusNode()];
  late final sharesFocusNodes = [for (final _ in purchases) FocusNode()];
  late final amountFocusNodes = [for (final _ in purchases) FocusNode()];
  DateTime date = DateTime.now();

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < purchases.length; i++) {
      priceFocusNodes[i].addListener(() {
        if (!priceFocusNodes[i].hasFocus) _recomputeAmountFromPriceOrShares(i);
      });
      sharesFocusNodes[i].addListener(() {
        if (!sharesFocusNodes[i].hasFocus) _recomputeAmountFromPriceOrShares(i);
      });
      amountFocusNodes[i].addListener(() {
        if (!amountFocusNodes[i].hasFocus) _recomputePriceFromAmount(i);
      });
    }
  }

  @override
  void dispose() {
    // Focus nodes first: their blur listeners write into the controllers.
    for (final node in [
      ...priceFocusNodes,
      ...sharesFocusNodes,
      ...amountFocusNodes,
    ]) {
      node.dispose();
    }
    for (final c in [
      ...amountControllers,
      ...sharesControllers,
      ...priceControllers,
      ...commissionControllers,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.'));

  // Montant = actions × prix unitaire is kept as an invariant, since the
  // real execution price often drifts from the recommendation (market
  // orders especially) — editing either the price or the total should
  // update the other rather than leaving the sheet with numbers that
  // don't actually multiply out.
  void _recomputeCommission(int i) {
    final amount = _parse(amountControllers[i]);
    if (amount == null) return;
    final commission =
        (amount * widget.commissionRatePct / 100 * 100).round() / 100;
    commissionControllers[i].text = commission.toStringAsFixed(2);
  }

  void _recomputeAmountFromPriceOrShares(int i) {
    final shares = _parse(sharesControllers[i]);
    final price = _parse(priceControllers[i]);
    if (shares == null || price == null) return;
    amountControllers[i].text = (shares * price).toStringAsFixed(2);
    _recomputeCommission(i);
  }

  void _recomputePriceFromAmount(int i) {
    final amount = _parse(amountControllers[i]);
    final shares = _parse(sharesControllers[i]);
    if (amount == null || shares == null || shares == 0) return;
    priceControllers[i].text = (amount / shares).toStringAsFixed(2);
    _recomputeCommission(i);
  }

  /// Applies the pending recompute of whichever field is still focused —
  /// its blur listener would only run after the sheet already popped.
  void _commitFocusedField() {
    for (var i = 0; i < purchases.length; i++) {
      if (priceFocusNodes[i].hasFocus || sharesFocusNodes[i].hasFocus) {
        _recomputeAmountFromPriceOrShares(i);
      } else if (amountFocusNodes[i].hasFocus) {
        _recomputePriceFromAmount(i);
      }
    }
  }

  List<InvestmentTransaction> _transactions() {
    _commitFocusedField();
    return [
      for (var i = 0; i < purchases.length; i++)
        InvestmentTransaction(
          date: date,
          isin: purchases[i].etf.isin,
          amountEur: _parse(amountControllers[i]) ?? purchases[i].amountEur,
          unitPrice: _parse(priceControllers[i]) ?? purchases[i].unitPrice,
          shares:
              _parse(sharesControllers[i]) ?? purchases[i].shares.toDouble(),
          commissionEur:
              _parse(commissionControllers[i]) ?? purchases[i].commissionEur,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        // Clears the opaque bar pinned over Android's nav bar area (see
        // the MaterialApp builder in main.dart), same as the +16 used on
        // every other edge here — not bottomSafePadding's extra +24,
        // which is tuned for the tail end of a scrolling list (blank
        // space is unremarkable there) and reads as an oversized gap
        // right under a single prominent button.
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              purchases.length > 1
                  ? 'Confirmer les transactions'
                  : 'Confirmer la transaction',
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
              Text(
                purchases[i].etf.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountControllers[i],
                focusNode: amountFocusNodes[i],
                decoration: const InputDecoration(labelText: 'Montant (€)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sharesControllers[i],
                focusNode: sharesFocusNodes[i],
                decoration: const InputDecoration(
                  labelText: "Nombre d'actions",
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceControllers[i],
                focusNode: priceFocusNodes[i],
                decoration: const InputDecoration(
                  labelText: 'Prix unitaire (€)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commissionControllers[i],
                decoration: const InputDecoration(labelText: 'Commission (€)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_transactions()),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
