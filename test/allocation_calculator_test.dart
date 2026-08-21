import 'package:etf_reminder/models/etf.dart';
import 'package:etf_reminder/services/allocation_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sum of absolute percentage-point deviation from target across every
/// holding, after applying a plan's purchases — the same metric the
/// calculator itself optimizes for.
double _deviationAfter(List<EtfHolding> holdings, MonthlyPlan plan) {
  final totalBefore = holdings.fold<double>(0, (s, h) => s + h.investedEur);
  final spend = plan.purchases.fold<double>(0, (s, p) => s + p.amountEur);
  final newTotal = totalBefore + spend;
  var deviation = 0.0;
  for (final h in holdings.where((h) => h.etf.targetPct > 0)) {
    final bought =
        plan.purchases.where((p) => p.etf.isin == h.etf.isin).fold<double>(0, (s, p) => s + p.amountEur);
    final newPct = (h.investedEur + bought) / newTotal * 100;
    deviation += (h.etf.targetPct - newPct).abs();
  }
  return deviation;
}

void main() {
  const bnp = Etf(isin: 'FR0011550193', name: 'BNP', category: 'Europe', targetPct: 80);
  const amundi = Etf(isin: 'FR0013412020', name: 'Amundi', category: 'Emergents', targetPct: 20);

  test('a budget with headroom above 2x the minimum order splits across ETFs '
      'instead of overshooting one', () {
    final holdings = [
      EtfHolding(etf: bnp, investedEur: 321.58, currentPrice: 21.57),
      EtfHolding(etf: amundi, investedEur: 0, currentPrice: 35.66),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: 500,
      minOrderAmount: 200,
      commissionRatePct: 0.5,
    );

    // Must not dump the whole budget into Amundi alone (old bug): that
    // would send Amundi to ~57% of the portfolio against an 80/20
    // (BNP/Amundi) target — far worse than splitting.
    expect(plan.purchases, isNotEmpty);
    final amundiSpend =
        plan.purchases.where((p) => p.etf.isin == amundi.isin).fold<double>(0, (s, p) => s + p.amountEur);
    expect(amundiSpend, lessThan(500));

    // No purchase should ever be sized below the minimum order.
    for (final p in plan.purchases) {
      expect(p.amountEur, greaterThanOrEqualTo(200));
    }

    // Splitting lands much closer to 80/20 than dumping everything on
    // Amundi alone would (deviation ~74pp).
    expect(_deviationAfter(holdings, plan), lessThan(20));
  });

  test('a budget sitting exactly at 2x the minimum order falls back to a single ETF '
      'rather than overshoot the budget by a lot to force a 2-way split', () {
    // Real case reported by the user: 400€ budget, 200€ minimum order, so a
    // 2-way split has zero slack — whole-share rounding on *both* legs
    // pushed the old (uncompensated) calculation to ~472€, 18% over
    // budget, instead of accepting a single, barely-rounded order.
    final holdings = [
      EtfHolding(etf: bnp, investedEur: 321.58, currentPrice: 21.57),
      EtfHolding(etf: amundi, investedEur: 0, currentPrice: 35.66),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: 400,
      minOrderAmount: 200,
      commissionRatePct: 0.5,
    );

    expect(plan.purchases, hasLength(1));
    final spend = plan.purchases.fold<double>(0, (s, p) => s + p.amountEur);
    // Ordinary single-order whole-share rounding slack only, not a 2-way
    // split's forced-minimum overshoot.
    expect(spend, lessThan(420));
  });

  test('a large budget rebalancing a lopsided target buys one right-sized order per ETF, '
      'not several minimum-sized ones on the same ETF', () {
    final holdings = [
      EtfHolding(etf: bnp, investedEur: 321.58, currentPrice: 21.6),
      EtfHolding(etf: amundi, investedEur: 0, currentPrice: 35.83),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: 900,
      minOrderAmount: 200,
      commissionRatePct: 0.5,
    );

    final bnpOrders = plan.purchases.where((p) => p.etf.isin == bnp.isin).toList();
    // The old bug produced 3 separate ~216€ BNP orders because each pass
    // undershot the amount actually needed to reach target (it ignored
    // that buying into BNP also grows the portfolio total, moving BNP's
    // own target up too) and kept falling back to the minimum-order floor.
    expect(bnpOrders, hasLength(1));

    final amundiOrders = plan.purchases.where((p) => p.etf.isin == amundi.isin).toList();
    expect(amundiOrders, hasLength(1));

    // With a budget this generous relative to the minimum order, the split
    // should land almost exactly on 80/20 (only whole-share rounding slack
    // left).
    expect(_deviationAfter(holdings, plan), lessThan(2));
  });

  test('a tight budget equal to the minimum order still buys the single most underweighted ETF', () {
    final holdings = [
      EtfHolding(etf: bnp, investedEur: 321.58, currentPrice: 21.08),
      EtfHolding(etf: amundi, investedEur: 0, currentPrice: 35.6),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: 200,
      minOrderAmount: 200,
      commissionRatePct: 0.5,
    );

    expect(plan.purchases, hasLength(1));
    expect(plan.purchases.single.etf.isin, amundi.isin);
  });

  test('already at target: the monthly budget still gets invested (never skipped), '
      'split however keeps the resulting deviation smallest', () {
    final holdings = [
      EtfHolding(etf: bnp, investedEur: 800, currentPrice: 21.08),
      EtfHolding(etf: amundi, investedEur: 200, currentPrice: 35.6),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: 400,
      minOrderAmount: 200,
      commissionRatePct: 0.5,
    );

    // Being exactly on target today doesn't mean "nothing to do" — the app
    // exists to keep investing a regular monthly amount, so the budget is
    // still deployed (proportionally to where it does the least damage to
    // the balance, which the minimum-order constraint can make an uneven
    // single order rather than a split — verified by hand for this case).
    expect(plan.purchases, isNotEmpty);
    final spend = plan.purchases.fold<double>(0, (s, p) => s + p.amountEur);
    expect(spend, greaterThan(0));
    expect(plan.unallocatedEur, lessThan(200));
  });

  test('a totally fresh portfolio (nothing invested yet) still proposes a first purchase', () {
    final holdings = [
      EtfHolding(etf: bnp, investedEur: 0, currentPrice: 21.08),
      EtfHolding(etf: amundi, investedEur: 0, currentPrice: 35.6),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: 200,
      minOrderAmount: 200,
      commissionRatePct: 0.5,
    );

    // 0/0 must not be read as "already balanced". With only one minimum
    // order affordable, funding the 80%-target ETF (BNP) alone lands
    // closer to target than funding the 20%-target one alone.
    expect(plan.purchases, hasLength(1));
    expect(plan.purchases.single.etf.isin, bnp.isin);
  });

  test('commission is 0.5% of the gross amount, rounded to the cent', () {
    const soleEtf = Etf(isin: 'FR0011550193', name: 'BNP', category: 'Europe', targetPct: 100);
    final holdings = [
      EtfHolding(etf: soleEtf, investedEur: 0, currentPrice: 18.464),
    ];

    final plan = AllocationCalculator().computeMonthlyPlan(
      holdings: holdings,
      availableBudget: 110.78,
      minOrderAmount: 110.78,
      commissionRatePct: 0.5,
    );

    expect(plan.purchases.single.shares, 6);
    expect(plan.purchases.single.amountEur, closeTo(110.78, 0.01));
    expect(plan.purchases.single.commissionEur, closeTo(0.55, 0.001));
  });
}
