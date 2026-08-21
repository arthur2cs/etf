class Etf {
  final String isin;
  final String name;
  final String category;
  final double targetPct;

  const Etf({
    required this.isin,
    required this.name,
    required this.category,
    required this.targetPct,
  });

  Etf copyWith({
    String? name,
    String? category,
    double? targetPct,
  }) {
    return Etf(
      isin: isin,
      name: name ?? this.name,
      category: category ?? this.category,
      targetPct: targetPct ?? this.targetPct,
    );
  }

  factory Etf.fromRow(List<Object?> row) {
    return Etf(
      isin: (row.elementAtOrNull(0) ?? '').toString(),
      name: (row.elementAtOrNull(1) ?? '').toString(),
      category: (row.elementAtOrNull(2) ?? '').toString(),
      targetPct: double.tryParse((row.elementAtOrNull(3) ?? '0').toString()) ?? 0,
    );
  }

  List<Object?> toRow() => [isin, name, category, targetPct];

  factory Etf.fromJson(Map<String, dynamic> json) => Etf(
        isin: json['isin'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        targetPct: (json['targetPct'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'isin': isin,
        'name': name,
        'category': category,
        'targetPct': targetPct,
      };
}

extension _ListElementAt on List<Object?> {
  Object? elementAtOrNull(int index) => index < length ? this[index] : null;
}
