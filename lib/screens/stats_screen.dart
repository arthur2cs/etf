import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inflation_rate.dart';
import '../models/investment_transaction.dart';
import '../services/portfolio_repository.dart';
import '../theme/app_theme.dart';

final _eur = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
final _compactEur = NumberFormat.compactCurrency(
  locale: 'fr_FR',
  symbol: '€',
  decimalDigits: 0,
);
const _monthAbbr = [
  'Jan',
  'Fév',
  'Mar',
  'Avr',
  'Mai',
  'Juin',
  'Juil',
  'Août',
  'Sep',
  'Oct',
  'Nov',
  'Déc',
];

class StatsScreen extends StatefulWidget {
  final PortfolioRepository repository;
  const StatsScreen({super.key, required this.repository});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  double _annualReturnPct = 7;
  int _horizonYears = 10;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final repo = widget.repository;
    final transactions = [...repo.transactions]
      ..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(title: const Text('Stats & projections')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding(context)),
        children: [
          Text(
            'Historique des versements',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (transactions.isEmpty)
            const Text('Pas encore de transaction enregistrée.')
          else
            _HistoryChart(transactions: transactions),
          const Divider(height: 32),
          Text('Projection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rendement annuel : ${_annualReturnPct.toStringAsFixed(1)}%',
                    ),
                    Slider(
                      value: _annualReturnPct,
                      min: 0,
                      max: 12,
                      divisions: 24,
                      label: '${_annualReturnPct.toStringAsFixed(1)}%',
                      onChanged: (v) => setState(() => _annualReturnPct = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Horizon : $_horizonYears ans'),
                    Slider(
                      value: _horizonYears.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$_horizonYears ans',
                      onChanged: (v) =>
                          setState(() => _horizonYears = v.round()),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Builder(
            builder: (context) {
              final projected = _projectFutureValue(
                presentValue: repo.totalInvested,
                monthlyContribution: repo.monthlyBudget,
                annualRatePct: _annualReturnPct,
                months: _horizonYears * 12,
              );
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      _eur.format(projected),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 32),
          Text(
            'Pouvoir d\'achat d\'aujourd\'hui',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _InflationSection(
            repo: repo,
            purchasingPower: _projectFutureValueNetOfInflation(
              presentValue: repo.totalInvested,
              monthlyContribution: repo.monthlyBudget,
              annualRatePct: _annualReturnPct,
              months: _horizonYears * 12,
              inflationRates: repo.inflationRates,
              from: DateTime.now(),
            ),
          ),
        ],
      ),
    );
  }

  /// Projects the nominal future balance at a constant monthly rate derived
  /// from [annualRatePct] — the raw return, with no inflation adjustment.
  double _projectFutureValue({
    required double presentValue,
    required double monthlyContribution,
    required double annualRatePct,
    required int months,
  }) {
    final monthlyRate = annualRatePct / 100 / 12;
    if (monthlyRate == 0) {
      return presentValue + monthlyContribution * months;
    }
    final growth = math.pow(1 + monthlyRate, months).toDouble();
    final futureOfPresent = presentValue * growth;
    final futureOfContributions =
        monthlyContribution * ((growth - 1) / monthlyRate);
    return futureOfPresent + futureOfContributions;
  }

  /// Same projection as [_projectFutureValue], but net of inflation, so the
  /// result reads in today's euros of purchasing power instead of nominal
  /// future euros: each month's return is the nominal [annualRatePct]
  /// deflated by that calendar year's inflation rate (Fisher equation),
  /// using the entered [inflationRates] where a year has one and their
  /// average for every other year — notably the projected years still
  /// ahead, which by definition have no entered rate.
  double _projectFutureValueNetOfInflation({
    required double presentValue,
    required double monthlyContribution,
    required double annualRatePct,
    required int months,
    required List<InflationRate> inflationRates,
    required DateTime from,
  }) {
    final inflationByYear = {for (final r in inflationRates) r.year: r.ratePct};
    final averageInflationPct = inflationRates.isEmpty
        ? 0.0
        : inflationRates.map((r) => r.ratePct).reduce((a, b) => a + b) /
              inflationRates.length;

    var balance = presentValue;
    for (var m = 1; m <= months; m++) {
      final year = DateTime(from.year, from.month + m).year;
      final inflationPct = inflationByYear[year] ?? averageInflationPct;
      final realAnnualRate =
          (1 + annualRatePct / 100) / (1 + inflationPct / 100) - 1;
      balance = balance * (1 + realAnnualRate / 12) + monthlyContribution;
    }
    return balance;
  }
}

enum _ChartGranularity { year, month }

class _HistoryChart extends StatefulWidget {
  final List<InvestmentTransaction> transactions;
  const _HistoryChart({required this.transactions});

  @override
  State<_HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<_HistoryChart> {
  _ChartGranularity _granularity = _ChartGranularity.month;
  late final PageController _yearPageController;
  late int _currentYearPage;

  // Index of the tapped-and-pinned spot in each chart, so its tooltip stays
  // up after the finger lifts instead of only showing while held down.
  int? _pinnedYearIndex;
  int? _pinnedMonthIndex;

  static int _monthIndex(DateTime d) => d.year * 12 + (d.month - 1);

  @override
  void initState() {
    super.initState();
    _currentYearPage = _years().length - 1;
    _yearPageController = PageController(initialPage: _currentYearPage);
  }

  @override
  void dispose() {
    _yearPageController.dispose();
    super.dispose();
  }

  /// Calendar years to page through in month-mode, oldest first — one
  /// investment-history page per year, defaulting to the most recent.
  List<int> _years() {
    final sorted = [...widget.transactions]
      ..sort((a, b) => a.date.compareTo(b.date));
    final startYear = sorted.first.date.year;
    final endYear = math.max(startYear, DateTime.now().year);
    return [for (var y = startYear; y <= endYear; y++) y];
  }

  /// Cumulative amount invested by the end of each calendar month, for
  /// every month between the first and last transaction (inclusive) — the
  /// curve's actual extent. Months outside that range simply have no
  /// entry: the line stops there even though the calendar month itself is
  /// still shown on the axis.
  Map<int, double> _monthlyCumulative() {
    final sorted = [...widget.transactions]
      ..sort((a, b) => a.date.compareTo(b.date));
    final startIdx = _monthIndex(sorted.first.date);
    final endIdx = _monthIndex(sorted.last.date);

    final byMonth = <int, double>{};
    for (final t in sorted) {
      final idx = _monthIndex(t.date);
      byMonth[idx] = (byMonth[idx] ?? 0) + t.amountEur;
    }

    var running = 0.0;
    final cumulative = <int, double>{};
    for (var i = startIdx; i <= endIdx; i++) {
      running += byMonth[i] ?? 0;
      cumulative[i] = running;
    }
    return cumulative;
  }

  /// Month indices (year*12 + month0) that had at least one transaction —
  /// these get a dot marker on the curve, unlike months just carried flat.
  Set<int> _monthsWithTransaction() =>
      widget.transactions.map((t) => _monthIndex(t.date)).toSet();

  /// Same idea as [_monthsWithTransaction], one entry per calendar year.
  Set<int> _yearsWithTransaction() =>
      widget.transactions.map((t) => t.date.year).toSet();

  /// Same idea as [_monthlyCumulative], one point per calendar year.
  List<MapEntry<int, double>> _yearlyCumulative() {
    final sorted = [...widget.transactions]
      ..sort((a, b) => a.date.compareTo(b.date));
    final startYear = sorted.first.date.year;
    final endYear = math.max(startYear, DateTime.now().year);

    final byYear = <int, double>{};
    for (final t in sorted) {
      byYear[t.date.year] = (byYear[t.date.year] ?? 0) + t.amountEur;
    }

    var running = 0.0;
    final result = <MapEntry<int, double>>[];
    for (var y = startYear; y <= endYear; y++) {
      running += byYear[y] ?? 0;
      result.add(MapEntry(y, running));
    }
    return result;
  }

  static const _niceSteps = [
    10.0,
    20.0,
    25.0,
    50.0,
    100.0,
    200.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    2500.0,
    5000.0,
    10000.0,
    20000.0,
    25000.0,
    50000.0,
    100000.0,
  ];

  /// A round Y-axis step (10/20/25/50/100/...) and the chart's actual
  /// maxY: a clean multiple of that step, strictly above the data, with a
  /// constant 8% of the total axis height held back above it as headroom
  /// for that top label. That headroom is deliberately a fraction of the
  /// *axis*, not of the step — sized as interval * 0.2 instead, it would
  /// shrink to near nothing whenever the data max lands close enough to a
  /// step multiple to force an extra full step (e.g. dataMax = 400 with a
  /// 100 step), clipping the top label right when it's closest to the edge.
  ({double interval, double maxY}) _niceYAxis(double dataMax) {
    final roughStep = dataMax <= 0 ? _niceSteps.first : dataMax / 5;
    final interval = _niceSteps.firstWhere(
      (s) => s >= roughStep,
      orElse: () => _niceSteps.last,
    );
    var topTick = interval * (dataMax / interval).ceil();
    if (topTick <= dataMax) topTick += interval;
    return (interval: interval, maxY: topTick / 0.92);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<_ChartGranularity>(
            segments: const [
              ButtonSegment(
                value: _ChartGranularity.year,
                label: Text('Année'),
              ),
              ButtonSegment(
                value: _ChartGranularity.month,
                label: Text('Mois'),
              ),
            ],
            selected: {_granularity},
            onSelectionChanged: (s) => setState(() => _granularity = s.first),
          ),
        ),
        const SizedBox(height: 8),
        _granularity == _ChartGranularity.year
            ? _buildYearChart(context)
            : _buildMonthChart(context),
      ],
    );
  }

  /// Shared shell for both chart views — fixed height, padding, and corner
  /// labels — so switching between "Année" and "Mois" never resizes the
  /// chart or shifts its labels; only the plotted content underneath
  /// differs.
  Widget _chartFrame({
    required Widget chart,
    required String leftLabel,
    required String rightLabel,
    Widget? badge,
  }) {
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 28, right: 24),
            child: chart,
          ),
          Positioned(
            top: 0,
            left: 4,
            child: IgnorePointer(
              child: Text(leftLabel, style: const TextStyle(fontSize: 10)),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 0,
            child: IgnorePointer(
              child: Text(rightLabel, style: const TextStyle(fontSize: 10)),
            ),
          ),
          if (badge != null) badge,
        ],
      ),
    );
  }

  static const _xAxisHeadroomFraction = 0.04;

  /// Right edge of the year chart's X axis: a constant fraction of the
  /// axis's own width held back past the last (current) year, so it stays
  /// discreet regardless of how many years of data exist — a fixed
  /// data-unit margin (like month's) would look disproportionately large
  /// with only a couple of years. Same idea as [_niceYAxis]'s headroom.
  double _yearAxisMaxX(int topIndex) {
    if (topIndex <= 0) return 0.4;
    return topIndex / (1 - _xAxisHeadroomFraction);
  }

  Widget _buildYearChart(BuildContext context) {
    final entries = _yearlyCumulative();
    final spots = [
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].value),
    ];
    final investedYears = _yearsWithTransaction();
    final maxY = spots.map((s) => s.y).fold<double>(0, math.max);
    final yAxis = _niceYAxis(maxY);
    final pinned =
        (_pinnedYearIndex != null && _pinnedYearIndex! < spots.length)
        ? _pinnedYearIndex
        : null;
    final barData = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: Theme.of(context).colorScheme.primary,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, bar) =>
            investedYears.contains(entries[spot.x.round()].key),
      ),
      showingIndicators: pinned == null ? const [] : [pinned],
    );

    return _chartFrame(
      leftLabel: 'Investi',
      rightLabel: 'Année',
      chart: LineChart(
        LineChartData(
          minX: 0,
          maxX: _yearAxisMaxX(entries.length - 1),
          minY: 0,
          maxY: yAxis.maxY,
          gridData: const FlGridData(show: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                // Without this, fl_chart forces an extra tick at the exact
                // (non-integer) maxX, duplicating/clipping the last label.
                maxIncluded: false,
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${entries[idx].key}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: yAxis.interval,
                // Without this, fl_chart forces an extra tick at the exact
                // maxY (the raw data max), even when it isn't a multiple
                // of interval — that's the label that was clipped.
                maxIncluded: false,
                getTitlesWidget: (value, meta) => Text(
                  _compactEur.format(value),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
          // Built-in touch handling shows the tooltip only while the
          // finger/pointer stays down. We handle taps ourselves instead,
          // so a tap pins the tooltip until another tap lands elsewhere
          // (fl_chart resolves a tap to no spot once it's more than
          // touchSpotThreshold px from any point on the x-axis).
          lineTouchData: LineTouchData(
            handleBuiltInTouches: false,
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent) return;
              final spots = response?.lineBarSpots;
              setState(
                () => _pinnedYearIndex = (spots == null || spots.isEmpty)
                    ? null
                    : spots.first.spotIndex,
              );
            },
            touchTooltipData: LineTouchTooltipData(
              fitInsideVertically: true,
              fitInsideHorizontally: true,
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final idx = spot.x.round();
                if (idx < 0 || idx >= entries.length) return null;
                final year = entries[idx].key;
                return LineTooltipItem(
                  '$year\n${_eur.format(spot.y)} cumulé',
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          showingTooltipIndicators: pinned == null
              ? const []
              : [
                  ShowingTooltipIndicators([
                    LineBarSpot(barData, 0, spots[pinned]),
                  ]),
                ],
          lineBarsData: [barData],
        ),
      ),
    );
  }

  Widget _buildMonthChart(BuildContext context) {
    final years = _years();
    final cumulative = _monthlyCumulative();
    final investedMonths = _monthsWithTransaction();

    return _chartFrame(
      leftLabel: 'Investi',
      rightLabel: 'Mois',
      badge: Positioned(
        top: 32,
        left: 56,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${years[_currentYearPage]}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
      ),
      chart: PageView.builder(
        controller: _yearPageController,
        itemCount: years.length,
        onPageChanged: (i) => setState(() {
          _currentYearPage = i;
          _pinnedMonthIndex = null;
        }),
        itemBuilder: (context, i) {
          final year = years[i];
          final spots = <FlSpot>[
            for (var m = 0; m < 12; m++)
              if (cumulative[year * 12 + m] case final value?)
                FlSpot(m.toDouble(), value),
          ];
          final maxY = spots.isEmpty
              ? 0.0
              : spots.map((s) => s.y).reduce(math.max);
          final yAxis = _niceYAxis(maxY);
          final pinned =
              (_pinnedMonthIndex != null && _pinnedMonthIndex! < spots.length)
              ? _pinnedMonthIndex
              : null;
          final barData = LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, bar) =>
                  investedMonths.contains(year * 12 + spot.x.round()),
            ),
            showingIndicators: pinned == null ? const [] : [pinned],
          );

          return LineChart(
            LineChartData(
              // A hair beyond the rightmost/topmost tick, so its
              // gridline (and centered label) doesn't sit exactly on
              // the chart's own border — which would visually cut the
              // label in half (this is how "Déc" was getting clipped).
              minX: 0,
              maxX: 11.4,
              minY: 0,
              maxY: yAxis.maxY,
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    // Without this, fl_chart forces an extra tick at
                    // the exact (non-integer) maxX, duplicating/
                    // clipping the last month's label.
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) {
                      final m = value.round();
                      if (m < 0 || m > 11) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _monthAbbr[m],
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    interval: yAxis.interval,
                    // Without this, fl_chart forces an extra tick at
                    // the exact maxY (the raw data max), even when it
                    // isn't a multiple of interval — the clipped label.
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) => Text(
                      _compactEur.format(value),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
              // Built-in touch handling shows the tooltip only while
              // the finger/pointer stays down. We handle taps
              // ourselves instead, so a tap pins the tooltip until
              // another tap lands elsewhere (fl_chart resolves a tap
              // to no spot once it's more than touchSpotThreshold px
              // from any point on the x-axis).
              lineTouchData: LineTouchData(
                handleBuiltInTouches: false,
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent) return;
                  final touched = response?.lineBarSpots;
                  setState(
                    () =>
                        _pinnedMonthIndex = (touched == null || touched.isEmpty)
                        ? null
                        : touched.first.spotIndex,
                  );
                },
                touchTooltipData: LineTouchTooltipData(
                  fitInsideVertically: true,
                  fitInsideHorizontally: true,
                  getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                    final m = spot.x.round();
                    final monthIdx = year * 12 + m;
                    final monthAmount = widget.transactions
                        .where((t) => _monthIndex(t.date) == monthIdx)
                        .fold<double>(0, (sum, t) => sum + t.amountEur);
                    final text = monthAmount > 0
                        ? '${_monthAbbr[m]} $year\n${_eur.format(spot.y)} cumulé\n'
                              '+${_eur.format(monthAmount)} ce mois-ci'
                        : '${_monthAbbr[m]} $year\n${_eur.format(spot.y)} cumulé';
                    return LineTooltipItem(
                      text,
                      const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ),
              showingTooltipIndicators: pinned == null
                  ? const []
                  : [
                      ShowingTooltipIndicators([
                        LineBarSpot(barData, 0, spots[pinned]),
                      ]),
                    ],
              lineBarsData: [barData],
            ),
          );
        },
      ),
    );
  }
}

class _InflationSection extends StatelessWidget {
  final PortfolioRepository repo;
  final double purchasingPower;
  const _InflationSection({required this.repo, required this.purchasingPower});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                _eur.format(purchasingPower),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Taux d\'inflation par année',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final rate in [
          ...repo.inflationRates,
        ]..sort((a, b) => a.year.compareTo(b.year)))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${rate.year}'),
            trailing: Text('${rate.ratePct.toStringAsFixed(1)}%'),
            onTap: () => _editRate(context, rate.year, rate.ratePct),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Ajouter / modifier une année'),
          onPressed: () => _editRate(context, now.year, 2),
        ),
      ],
    );
  }

  Future<void> _editRate(
    BuildContext context,
    int defaultYear,
    double defaultRate,
  ) async {
    final yearController = TextEditingController(text: defaultYear.toString());
    final rateController = TextEditingController(
      text: defaultRate.toStringAsFixed(1),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Taux d\'inflation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: yearController,
              decoration: const InputDecoration(labelText: 'Année'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: rateController,
              decoration: const InputDecoration(labelText: 'Taux (%)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (result == true) {
      final year = int.tryParse(yearController.text);
      final rate = double.tryParse(rateController.text.replaceAll(',', '.'));
      if (year != null && rate != null) {
        await repo.upsertInflationRate(
          InflationRate(year: year, ratePct: rate),
        );
      }
    }
  }
}
