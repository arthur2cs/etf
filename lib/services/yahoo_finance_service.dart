import 'dart:convert';

import 'package:http/http.dart' as http;

class PriceFetchException implements Exception {
  final String message;
  PriceFetchException(this.message);

  @override
  String toString() => 'PriceFetchException: $message';
}

const _userAgent = {'User-Agent': 'Mozilla/5.0 (etf_reminder app)'};

/// Fetches ETF prices from Yahoo Finance's public (unofficial) endpoints.
/// No API key required, but they're not officially supported and could
/// change without notice.
///
/// ISINs don't reliably map to a Yahoo ticker by just appending ".PA" —
/// some ETFs are listed under a different exchange/mnemonic (e.g.
/// FR0011550193 trades as ETZ.PA/ETSZ.DE, not FR0011550193.PA, which
/// returns stale zero data on Yahoo). So every ISIN is first resolved to
/// its actual Yahoo symbol via the search endpoint, then quoted.
class YahooFinanceService {
  static const _searchUrl = 'https://query2.finance.yahoo.com/v1/finance/search';
  static const _chartUrl = 'https://query1.finance.yahoo.com/v8/finance/chart';

  final Map<String, String> _resolvedSymbolCache = {};

  Future<String> _resolveSymbol(String isin) async {
    final cached = _resolvedSymbolCache[isin];
    if (cached != null) return cached;

    final uri = Uri.parse('$_searchUrl?q=$isin');
    final response = await http.get(uri, headers: _userAgent);
    if (response.statusCode != 200) {
      throw PriceFetchException('Recherche Yahoo Finance impossible pour $isin (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final quotes = (body['quotes'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final etfQuotes = quotes.where((q) => q['quoteType'] == 'ETF').toList();
    final candidates = etfQuotes.isNotEmpty ? etfQuotes : quotes;
    if (candidates.isEmpty) {
      throw PriceFetchException('Aucun ticker Yahoo Finance trouvé pour $isin');
    }

    final best = candidates.firstWhere(
      (q) => q['exchange'] == 'PAR',
      orElse: () => candidates.first,
    );
    final symbol = best['symbol'] as String?;
    if (symbol == null) {
      throw PriceFetchException('Aucun ticker Yahoo Finance trouvé pour $isin');
    }
    _resolvedSymbolCache[isin] = symbol;
    return symbol;
  }

  Future<double> fetchLatestPrice(String isin) async {
    final symbol = await _resolveSymbol(isin);
    final uri = Uri.parse('$_chartUrl/$symbol?interval=1d&range=1d');
    final response = await http.get(uri, headers: _userAgent);

    if (response.statusCode != 200) {
      throw PriceFetchException('Yahoo Finance a répondu ${response.statusCode} pour $symbol');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final chart = body['chart'] as Map<String, dynamic>?;
    final error = chart?['error'];
    if (error != null) {
      throw PriceFetchException('Erreur Yahoo Finance pour $symbol : $error');
    }

    final results = chart?['result'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw PriceFetchException('Aucune donnée Yahoo Finance pour $symbol');
    }

    final meta = results.first['meta'] as Map<String, dynamic>?;
    final price = meta?['regularMarketPrice'];
    if (price is! num || price <= 0) {
      throw PriceFetchException('Prix invalide renvoyé par Yahoo Finance pour $symbol');
    }
    return price.toDouble();
  }

  /// Fetches each ISIN independently: a failure on one ETF (e.g. a wrong
  /// ISIN or a delisted ETF) must not prevent the others from updating.
  /// Returns a map keyed by ISIN.
  Future<Map<String, double>> fetchLatestPrices(List<String> isins) async {
    final prices = <String, double>{};
    for (final isin in isins) {
      try {
        prices[isin] = await fetchLatestPrice(isin);
      } catch (_) {
        // Skipped: keep whatever price was previously cached for this ISIN.
      }
    }
    return prices;
  }
}
