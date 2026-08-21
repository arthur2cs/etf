class InflationRate {
  final int year;
  final double ratePct;

  const InflationRate({required this.year, required this.ratePct});

  factory InflationRate.fromRow(List<Object?> row) {
    return InflationRate(
      year: int.tryParse((row.elementAtOrNull(0) ?? '0').toString()) ?? 0,
      ratePct: double.tryParse((row.elementAtOrNull(1) ?? '0').toString()) ?? 0,
    );
  }

  List<Object?> toRow() => [year, ratePct];

  factory InflationRate.fromJson(Map<String, dynamic> json) => InflationRate(
        year: json['year'] as int,
        ratePct: (json['ratePct'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'year': year, 'ratePct': ratePct};
}

extension _ListElementAt on List<Object?> {
  Object? elementAtOrNull(int index) => index < length ? this[index] : null;
}
