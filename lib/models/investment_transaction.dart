class InvestmentTransaction {
  final DateTime date;
  final String isin;

  /// Gross share cost (shares × unitPrice) — kept consistent with how the
  /// rest of the app (allocation calculator, target %) reasons about
  /// invested capital, unaffected by broker fees.
  final double amountEur;
  final double unitPrice;
  final double shares;

  /// BoursoBank commission paid on top of [amountEur]. Real cash out of
  /// pocket = amountEur + commissionEur.
  final double commissionEur;

  const InvestmentTransaction({
    required this.date,
    required this.isin,
    required this.amountEur,
    required this.unitPrice,
    required this.shares,
    this.commissionEur = 0,
  });

  double get netAmountEur => amountEur + commissionEur;

  factory InvestmentTransaction.fromRow(List<Object?> row) {
    return InvestmentTransaction(
      date: _parseSheetsDate(row.elementAtOrNull(0)),
      isin: (row.elementAtOrNull(1) ?? '').toString(),
      amountEur: double.tryParse((row.elementAtOrNull(2) ?? '0').toString()) ?? 0,
      unitPrice: double.tryParse((row.elementAtOrNull(3) ?? '0').toString()) ?? 0,
      shares: double.tryParse((row.elementAtOrNull(4) ?? '0').toString()) ?? 0,
      commissionEur: double.tryParse((row.elementAtOrNull(5) ?? '0').toString()) ?? 0,
    );
  }

  List<Object?> toRow() => [
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        isin,
        amountEur,
        unitPrice,
        shares,
        commissionEur,
      ];

  factory InvestmentTransaction.fromJson(Map<String, dynamic> json) => InvestmentTransaction(
        date: DateTime.parse(json['date'] as String),
        isin: json['isin'] as String,
        amountEur: (json['amountEur'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        shares: (json['shares'] as num).toDouble(),
        commissionEur: (json['commissionEur'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'isin': isin,
        'amountEur': amountEur,
        'unitPrice': unitPrice,
        'shares': shares,
        'commissionEur': commissionEur,
      };
}

extension _ListElementAt on List<Object?> {
  Object? elementAtOrNull(int index) => index < length ? this[index] : null;
}

/// Google Sheets can hand back a date either as an ISO string (text cells,
/// including everything this app itself writes) or as a date serial number
/// (day count since 1899-12-30 — what a UI-typed, auto-detected date cell
/// returns under UNFORMATTED_VALUE). Both are locale-independent, unlike
/// the FORMATTED_VALUE string Sheets would otherwise render.
DateTime _parseSheetsDate(Object? raw) {
  if (raw is num) {
    return DateTime.utc(1899, 12, 30).add(Duration(days: raw.round()));
  }
  return DateTime.parse((raw ?? '').toString());
}
