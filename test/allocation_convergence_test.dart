import 'package:etf_reminder/models/etf.dart';
import 'package:etf_reminder/services/allocation_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sum of absolute percentage-point deviation from target across every
/// eligible holding.
double _deviation(List<Etf> etfs, Map<String, double> invested) {
  final total = invested.values.fold<double>(0, (s, v) => s + v);
  if (total <= 0) return etfs.fold<double>(0, (s, e) => s + e.targetPct);
  var deviation = 0.0;
  for (final e in etfs.where((e) => e.targetPct > 0)) {
    final pct = (invested[e.isin] ?? 0) / total * 100;
    deviation += (e.targetPct - pct).abs();
  }
  return deviation;
}

/// Runs the calculator month after month, applying each month's purchases
/// to a running `invested` map (fixed prices — this test is about the
/// allocation logic converging, not about price movements), and returns
/// the deviation from target measured at the end of every month.
List<double> _simulateMonths({
  required List<Etf> etfs,
  required Map<String, double> prices,
  required Map<String, double> startInvested,
  required double monthlyBudget,
  required double minOrderAmount,
  required int months,
}) {
  final invested = Map<String, double>.from(startInvested);
  final deviations = <double>[];

  for (var month = 0; month < months; month++) {
    final holdings = [
      for (final e in etfs)
        EtfHolding(etf: e, investedEur: invested[e.isin] ?? 0, currentPrice: prices[e.isin]),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: monthlyBudget,
      minOrderAmount: minOrderAmount,
      commissionRatePct: 0.5,
    );

    for (final purchase in plan.purchases) {
      invested[purchase.etf.isin] = (invested[purchase.etf.isin] ?? 0) + purchase.amountEur;
    }

    deviations.add(_deviation(etfs, invested));
  }

  return deviations;
}

void main() {
  test('a lopsided 80/20 target converges from a fresh portfolio within a couple of years', () {
    const bnp = Etf(isin: 'FR0011550193', name: 'BNP', category: 'Europe', targetPct: 80);
    const amundi = Etf(isin: 'FR0013412020', name: 'Amundi', category: 'Emergents', targetPct: 20);

    final deviations = _simulateMonths(
      etfs: [bnp, amundi],
      prices: {bnp.isin: 21.57, amundi.isin: 35.66},
      startInvested: {},
      monthlyBudget: 300,
      minOrderAmount: 200,
      months: 24,
    );

    // Starting from nothing, the very first month can only fund one ETF
    // (budget doesn't cover two minimum orders yet as a fresh 0€ base), so
    // deviation starts high — but it should trend down and settle small.
    expect(deviations.first, greaterThan(20));
    expect(deviations.last, lessThan(5));

    // The second half of the simulation should be consistently close to
    // target, not just a single lucky month.
    final secondHalf = deviations.sublist(12);
    for (final d in secondHalf) {
      expect(d, lessThan(10), reason: 'deviation stayed high: $secondHalf');
    }
  });

  test('a 3-ETF target (50/30/20) converges from a fresh portfolio', () {
    const core = Etf(isin: 'CORE', name: 'Core', category: 'World', targetPct: 50);
    const growth = Etf(isin: 'GROWTH', name: 'Growth', category: 'US', targetPct: 30);
    const em = Etf(isin: 'EM', name: 'Emerging', category: 'Emergents', targetPct: 20);

    final deviations = _simulateMonths(
      etfs: [core, growth, em],
      prices: {core.isin: 45.20, growth.isin: 62.10, em.isin: 18.75},
      startInvested: {},
      monthlyBudget: 500,
      minOrderAmount: 200,
      months: 24,
    );

    expect(deviations.last, lessThan(5));
    final secondHalf = deviations.sublist(12);
    for (final d in secondHalf) {
      expect(d, lessThan(10), reason: 'deviation stayed high: $secondHalf');
    }
  });

  test('an already-lopsided portfolio (100% on one ETF) rebalances towards 80/20 over time', () {
    const bnp = Etf(isin: 'FR0011550193', name: 'BNP', category: 'Europe', targetPct: 80);
    const amundi = Etf(isin: 'FR0013412020', name: 'Amundi', category: 'Emergents', targetPct: 20);

    final deviations = _simulateMonths(
      etfs: [bnp, amundi],
      prices: {bnp.isin: 21.57, amundi.isin: 35.66},
      startInvested: {bnp.isin: 1000, amundi.isin: 0},
      monthlyBudget: 300,
      minOrderAmount: 200,
      months: 24,
    );

    // Starts fully lopsided (100/0 vs. an 80/20 target -> 40pp deviation).
    expect(deviations.first, lessThan(40));
    // Trends towards target and stays there.
    expect(deviations.last, lessThan(5));
    for (var i = 1; i < deviations.length; i++) {
      // Deviation shouldn't blow back up once it's gotten close.
      if (deviations[i - 1] < 10) {
        expect(deviations[i], lessThan(15), reason: 'deviation spiked back up at month $i: $deviations');
      }
    }
  });
}
