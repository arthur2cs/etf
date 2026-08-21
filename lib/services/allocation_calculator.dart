import '../models/etf.dart';

class EtfHolding {
  final Etf etf;
  final double investedEur;
  final double? currentPrice;

  const EtfHolding({
    required this.etf,
    required this.investedEur,
    required this.currentPrice,
  });
}

/// One order to place this month, on one ETF.
class PlannedPurchase {
  final Etf etf;
  final double unitPrice;
  final int shares;

  /// Gross share cost (shares × unitPrice).
  final double amountEur;

  /// Estimated BoursoBank commission on top of [amountEur], from the
  /// commission rate setting.
  final double commissionEur;

  /// What to actually transfer to the PEA for this order: amountEur +
  /// commissionEur.
  double get totalToTransfer => amountEur + commissionEur;

  const PlannedPurchase({
    required this.etf,
    required this.unitPrice,
    required this.shares,
    required this.amountEur,
    required this.commissionEur,
  });
}

/// A month's worth of orders — usually one, but several when the monthly
/// budget comfortably covers more than one minimum order and spreading
/// across ETFs gets closer to the target allocation than concentrating
/// everything on a single one.
class MonthlyPlan {
  final List<PlannedPurchase> purchases;

  /// Budget left over after planning, too small to place another minimum
  /// order (or the portfolio reached its target before the budget ran out).
  final double unallocatedEur;

  const MonthlyPlan({required this.purchases, required this.unallocatedEur});

  double get totalToTransfer => purchases.fold(0, (sum, p) => sum + p.totalToTransfer);
}

class AllocationError implements Exception {
  final String message;
  AllocationError(this.message);

  @override
  String toString() => message;
}

/// Decides which ETF(s) to buy this month and for how much, so the
/// portfolio ends up as close as possible to its target allocation while
/// respecting BoursoBank's minimum order amount and whole-share purchases.
///
/// The core idea: solve for the continuous (not-yet-rounded-to-shares)
/// split that would land exactly on target if the whole budget were spent
/// in the right proportions, accounting for what's already invested
/// (`x_i = target%_i × (total + budget) − invested_i`). ETFs already at or
/// above target get nothing (buying more never helps).
///
/// Rounding to whole shares and to the minimum order amount can push a
/// small ideal allocation either up to the minimum or down to zero — no
/// fixed rule ("always floor" / "always skip") is correct in general, it
/// depends on the numbers (verified: each direction wins in different
/// concrete cases). So every combination of which underweighted ETFs get
/// funded this month is tried (their number is always small in practice),
/// and whichever combination lands closest to target overall — summed
/// absolute percentage-point deviation across every ETF — is picked.
class AllocationCalculator {
  MonthlyPlan computeMonthlyPlan({
    required List<EtfHolding> holdings,
    required double availableBudget,
    required double minOrderAmount,
    required double commissionRatePct,
  }) {
    final eligible = holdings.where((h) => h.etf.targetPct > 0).toList();
    if (eligible.isEmpty) {
      throw AllocationError(
        'Aucun ETF avec une répartition cible > 0 %. Règle au moins un % cible dans les réglages.',
      );
    }

    final totalTargetPct = eligible.fold<double>(0, (sum, h) => sum + h.etf.targetPct);
    if ((totalTargetPct - 100).abs() > 0.01) {
      throw AllocationError(
        'La somme des % cible (${totalTargetPct.toStringAsFixed(1)}%) ne fait pas 100 %. Corrige la répartition dans les réglages.',
      );
    }

    if (availableBudget < minOrderAmount) {
      return MonthlyPlan(purchases: const [], unallocatedEur: availableBudget < 0 ? 0 : availableBudget);
    }

    final totalBefore = holdings.fold<double>(0, (sum, h) => sum + h.investedEur);
    final totalAfterFull = totalBefore + availableBudget;

    // ETFs already at or above their target: buying more only makes things
    // worse, so they're never candidates for this month's purchases.
    final candidates = eligible.where((h) {
      final naiveTarget = h.etf.targetPct / 100 * totalAfterFull - h.investedEur;
      return naiveTarget > 0;
    }).toList();

    if (candidates.isEmpty) {
      return MonthlyPlan(purchases: const [], unallocatedEur: availableBudget);
    }

    List<PlannedPurchase>? bestPurchases;
    double bestSpend = 0;
    double bestDeviation = double.infinity;
    var anyPriceAvailable = false;

    final n = candidates.length;
    for (var mask = 1; mask < (1 << n); mask++) {
      final subset = <EtfHolding>[
        for (var i = 0; i < n; i++)
          if (mask & (1 << i) != 0) candidates[i],
      ];

      // Can't afford a minimum order for every member of this subset.
      if (subset.length * minOrderAmount > availableBudget) continue;
      if (subset.any((h) => h.currentPrice == null || h.currentPrice! <= 0)) continue;
      anyPriceAvailable = true;

      final purchases = _evaluateSubset(
        subset: subset,
        availableBudget: availableBudget,
        minOrderAmount: minOrderAmount,
        commissionRatePct: commissionRatePct,
      );
      if (purchases == null) continue;

      final spend = purchases.fold<double>(0, (sum, p) => sum + p.amountEur);
      final newTotal = totalBefore + spend;
      if (newTotal <= 0) continue;

      var deviation = 0.0;
      for (final h in eligible) {
        final bought = purchases
            .where((p) => p.etf.isin == h.etf.isin)
            .fold<double>(0, (sum, p) => sum + p.amountEur);
        final newPct = (h.investedEur + bought) / newTotal * 100;
        deviation += (h.etf.targetPct - newPct).abs();
      }

      final isBetter = bestPurchases == null ||
          deviation < bestDeviation - 1e-9 ||
          (deviation < bestDeviation + 1e-9 &&
              (spend > bestSpend + 1e-9 ||
                  (spend > bestSpend - 1e-9 && purchases.length < bestPurchases.length)));
      if (isBetter) {
        bestDeviation = deviation;
        bestSpend = spend;
        bestPurchases = purchases..sort((a, b) => a.etf.isin.compareTo(b.etf.isin));
      }
    }

    if (bestPurchases == null) {
      if (!anyPriceAvailable) {
        throw AllocationError(
          'Prix indisponible pour calculer le plan du mois. Réessaie plus tard.',
        );
      }
      // Prices are there, but no combination fits the budget (e.g. several
      // underweighted ETFs and not enough room for even one minimum order
      // given how the check above works out) — nothing sensible to propose.
      return MonthlyPlan(purchases: const [], unallocatedEur: availableBudget);
    }

    final unallocated = availableBudget - bestSpend;
    return MonthlyPlan(purchases: bestPurchases, unallocatedEur: unallocated < 0 ? 0 : unallocated);
  }

  /// Sizes a purchase for every member of [subset], given they'll share
  /// [availableBudget] in proportion to their targets. Returns `null` if
  /// the subset can't be funded without a member's order falling below
  /// [minOrderAmount].
  ///
  /// A member whose proportional share doesn't clear the minimum order is
  /// floored up to it — but that money has to come from somewhere, so the
  /// other (still-free) members' shares are recomputed on what's left
  /// after the floored ones are set aside, rather than each member getting
  /// its "as if it were the only line needing adjustment" ideal
  /// independently. Without this, a floored member's forced minimum
  /// doesn't reduce anyone else's spend, and the combination can overshoot
  /// the budget by far more than ordinary whole-share rounding (a real
  /// case: 400€ budget, 80/20 target, ended up recommending 472€ because
  /// the underweighted ETF was floored to its 200€ minimum on top of the
  /// other ETF's own full, un-adjusted ideal amount).
  ///
  /// If flooring one member pushes what's left below what the remaining
  /// free members need for their own minimum orders, one of those is
  /// floored too, and so on — bounded by the subset's size — until either
  /// everyone still free clears the minimum, or funding the subset proves
  /// impossible within budget.
  List<PlannedPurchase>? _evaluateSubset({
    required List<EtfHolding> subset,
    required double availableBudget,
    required double minOrderAmount,
    required double commissionRatePct,
  }) {
    final free = List<EtfHolding>.from(subset);
    final flooredShares = <String, int>{}; // isin -> fixed share count
    double flooredSpend = 0;

    Map<String, double>? idealForFree;

    while (true) {
      if (free.isEmpty) break;

      final budgetForFree = availableBudget - flooredSpend;
      if (budgetForFree < free.length * minOrderAmount) return null;

      final sumFreeTargetPct = free.fold<double>(0, (sum, h) => sum + h.etf.targetPct);
      final sumFreeInvested = free.fold<double>(0, (sum, h) => sum + h.investedEur);
      final subTotalAfterFree = sumFreeInvested + budgetForFree;

      final ideal = <String, double>{
        for (final h in free)
          h.etf.isin: (h.etf.targetPct / sumFreeTargetPct) * subTotalAfterFree - h.investedEur,
      };

      EtfHolding? worst;
      for (final h in free) {
        if (ideal[h.etf.isin]! < minOrderAmount) {
          if (worst == null || ideal[h.etf.isin]! < ideal[worst.etf.isin]!) worst = h;
        }
      }

      if (worst == null) {
        idealForFree = ideal;
        break;
      }

      final price = worst.currentPrice!;
      final minShares = (minOrderAmount / price).ceil();
      flooredShares[worst.etf.isin] = minShares;
      flooredSpend += minShares * price;
      free.remove(worst);
    }

    final purchases = <PlannedPurchase>[];
    for (final h in subset) {
      final price = h.currentPrice!;
      int shares;
      final fixedShares = flooredShares[h.etf.isin];
      if (fixedShares != null) {
        shares = fixedShares;
      } else {
        final minShares = (minOrderAmount / price).ceil();
        final roundedShares = (idealForFree![h.etf.isin]! / price).round();
        shares = roundedShares < minShares ? minShares : roundedShares;
      }
      final amountEur = shares * price;
      purchases.add(PlannedPurchase(
        etf: h.etf,
        unitPrice: price,
        shares: shares,
        amountEur: amountEur,
        commissionEur: _roundCents(amountEur * commissionRatePct / 100),
      ));
    }
    return purchases;
  }

  double _roundCents(double value) => (value * 100).round() / 100;
}
