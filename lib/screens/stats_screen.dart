import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inflation_rate.dart';
import '../models/investment_transaction.dart';
import '../services/portfolio_repository.dart';

final _eur = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

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
    final transactions = [...repo.transactions]..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(title: const Text('Stats & projections')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Historique des versements', style: Theme.of(context).textTheme.titleMedium),
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
                    Text('Rendement annuel : ${_annualReturnPct.toStringAsFixed(1)}%'),
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
                      onChanged: (v) => setState(() => _horizonYears = v.round()),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Builder(builder: (context) {
            final projected = _projectFutureValue(
              presentValue: repo.totalInvested,
              monthlyContribution: repo.monthlyBudget,
              annualRatePct: _annualReturnPct,
              months: _horizonYears * 12,
            );
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Dans $_horizonYears ans, en continuant à investir ${_eur.format(repo.monthlyBudget)}/mois '
                  'à ${_annualReturnPct.toStringAsFixed(1)}%/an : ${_eur.format(projected)}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            );
          }),
          const Divider(height: 32),
          Text('Inflation', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _InflationSection(repo: repo, transactions: transactions),
        ],
      ),
    );
  }

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
    final futureOfContributions = monthlyContribution * ((growth - 1) / monthlyRate);
    return futureOfPresent + futureOfContributions;
  }
}

class _HistoryChart extends StatelessWidget {
  final List<InvestmentTransaction> transactions;
  const _HistoryChart({required this.transactions});

  @override
  Widget build(BuildContext context) {
    double cumulative = 0;
    final spots = <FlSpot>[];
    for (var i = 0; i < transactions.length; i++) {
      cumulative += transactions[i].amountEur;
      spots.add(FlSpot(i.toDouble(), cumulative));
    }
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: true),
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _InflationSection extends StatelessWidget {
  final PortfolioRepository repo;
  final List<InvestmentTransaction> transactions;
  const _InflationSection({required this.repo, required this.transactions});

  double _inflationFactor(DateTime from, DateTime to, List<InflationRate> rates) {
    final rateByYear = {for (final r in rates) r.year: r.ratePct / 100};
    double factor = 1.0;
    for (var year = from.year; year <= to.year; year++) {
      final annualRate = rateByYear[year] ?? 0;
      final yearStart = DateTime(year, 1, 1);
      final yearEndExclusive = DateTime(year + 1, 1, 1);
      final periodStart = from.isAfter(yearStart) ? from : yearStart;
      final periodEnd = to.isBefore(yearEndExclusive) ? to : yearEndExclusive;
      final daysInYear = yearEndExclusive.difference(yearStart).inDays;
      final daysInPeriod = periodEnd.difference(periodStart).inDays.clamp(0, daysInYear);
      final fraction = daysInPeriod / daysInYear;
      factor *= math.pow(1 + annualRate, fraction);
    }
    return factor;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    double nominalTotal = 0;
    double inflationAdjustedTotal = 0;
    double totalCommission = 0;
    final sharesByIsin = <String, double>{};

    for (final t in transactions) {
      // Real cash out of pocket (share cost + broker commission), so the
      // inflation comparison reflects what actually left the bank account.
      nominalTotal += t.netAmountEur;
      inflationAdjustedTotal += t.netAmountEur * _inflationFactor(t.date, now, repo.inflationRates);
      totalCommission += t.commissionEur;
      sharesByIsin.update(t.isin, (v) => v + t.shares, ifAbsent: () => t.shares);
    }

    double? marketValue;
    if (sharesByIsin.isNotEmpty && repo.pricesByIsin.isNotEmpty) {
      marketValue = 0;
      for (final entry in sharesByIsin.entries) {
        final price = repo.pricesByIsin[entry.key];
        if (price == null) {
          marketValue = null;
          break;
        }
        marketValue = marketValue! + entry.value * price;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Investi (euros courants) : ${_eur.format(nominalTotal)}'),
                Text('dont commissions BoursoBank : ${_eur.format(totalCommission)}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text('Équivalent en euros d\'aujourd\'hui : ${_eur.format(inflationAdjustedTotal)}'),
                if (marketValue != null)
                  Text('Valeur de marché actuelle : ${_eur.format(marketValue)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Taux d\'inflation par année', style: Theme.of(context).textTheme.titleSmall),
        for (final rate in [...repo.inflationRates]..sort((a, b) => a.year.compareTo(b.year)))
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

  Future<void> _editRate(BuildContext context, int defaultYear, double defaultRate) async {
    final yearController = TextEditingController(text: defaultYear.toString());
    final rateController = TextEditingController(text: defaultRate.toStringAsFixed(1));

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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Enregistrer')),
        ],
      ),
    );

    if (result == true) {
      final year = int.tryParse(yearController.text);
      final rate = double.tryParse(rateController.text.replaceAll(',', '.'));
      if (year != null && rate != null) {
        await repo.upsertInflationRate(InflationRate(year: year, ratePct: rate));
      }
    }
  }
}
