import 'package:flutter/foundation.dart';

import '../models/etf.dart';
import '../models/inflation_rate.dart';
import '../models/investment_transaction.dart';
import 'allocation_calculator.dart';
import 'local_cache_service.dart';
import 'sheets_service.dart';
import 'yahoo_finance_service.dart';

/// Central app state: holds the ETF config, transaction history, inflation
/// table, cached prices and user settings. Loads instantly from local
/// cache, then re-syncs with Google Sheets (the source of truth) whenever
/// possible.
class PortfolioRepository extends ChangeNotifier {
  final SheetsService _sheetsService;
  final YahooFinanceService _priceService;
  final LocalCacheService _cache;

  PortfolioRepository({
    SheetsService? sheetsService,
    YahooFinanceService? priceService,
    LocalCacheService? cacheService,
  })  : _sheetsService = sheetsService ?? SheetsService(),
        _priceService = priceService ?? YahooFinanceService(),
        _cache = cacheService ?? LocalCacheService();

  List<Etf> etfs = [];
  List<InvestmentTransaction> transactions = [];
  List<InflationRate> inflationRates = [];
  Map<String, double> pricesByIsin = {};
  DateTime? pricesFetchedAt;

  double monthlyBudget = 200;
  double minOrderAmount = 200;
  double commissionRatePct = 0.5;
  bool reminderEnabled = true;
  int reminderDay = 1;
  int reminderHour = 9;
  int reminderMinute = 0;

  bool isSignedIn = false;
  bool isSyncing = false;
  String? lastError;

  Future<void> init() async {
    etfs = await _cache.loadEtfs();
    transactions = await _cache.loadTransactions();
    inflationRates = await _cache.loadInflationRates();
    pricesByIsin = await _cache.loadPrices();
    pricesFetchedAt = await _cache.pricesFetchedAt();
    monthlyBudget = await _cache.monthlyBudget();
    minOrderAmount = await _cache.minOrderAmount();
    commissionRatePct = await _cache.commissionRatePct();
    reminderEnabled = await _cache.reminderEnabled();
    reminderDay = await _cache.reminderDay();
    reminderHour = await _cache.reminderHour();
    reminderMinute = await _cache.reminderMinute();
    notifyListeners();

    try {
      final account = await _sheetsService.signInSilently();
      isSignedIn = account != null;
    } catch (_) {
      // No cached Google session (or Google Play services unavailable) —
      // the user can still sign in manually from the home screen.
      isSignedIn = false;
    }
    notifyListeners();
    if (isSignedIn) {
      await syncFromSheets();
    }
    // Price fetching doesn't depend on Google Sheets, so it runs regardless
    // of sign-in state.
    await refreshPrices();
  }

  Future<void> signIn() async {
    await _sheetsService.signIn();
    isSignedIn = true;
    notifyListeners();
    await syncFromSheets();
    await refreshPrices();
  }

  Future<void> syncFromSheets() async {
    isSyncing = true;
    lastError = null;
    notifyListeners();
    try {
      final configRows = await _sheetsService.readConfigRows();
      etfs = configRows.where((r) => r.isNotEmpty).map(Etf.fromRow).toList();
      await _cache.saveEtfs(etfs);

      final txRows = await _sheetsService.readTransactionRows();
      transactions = txRows.where((r) => r.isNotEmpty).map(InvestmentTransaction.fromRow).toList();
      await _cache.saveTransactions(transactions);

      final inflationRows = await _sheetsService.readInflationRows();
      inflationRates = inflationRows.where((r) => r.isNotEmpty).map(InflationRate.fromRow).toList();
      await _cache.saveInflationRates(inflationRates);
    } catch (e) {
      lastError = 'Synchronisation Google Sheets impossible : $e';
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshPrices() async {
    if (etfs.isEmpty) return;
    lastError = null;
    try {
      final prices = await _priceService.fetchLatestPrices(etfs.map((e) => e.isin).toList());
      pricesByIsin.addAll(prices);
      pricesFetchedAt = DateTime.now();
      await _cache.savePrices(pricesByIsin);
    } catch (e) {
      lastError = 'Récupération des prix impossible : $e';
    } finally {
      notifyListeners();
    }
  }

  Future<void> addOrUpdateEtf(Etf etf) async {
    final index = etfs.indexWhere((e) => e.isin == etf.isin);
    if (index >= 0) {
      etfs[index] = etf;
    } else {
      etfs.add(etf);
    }
    await _persistEtfs();
    await refreshPrices();
  }

  Future<void> removeEtf(String isin) async {
    etfs.removeWhere((e) => e.isin == isin);
    await _persistEtfs();
  }

  Future<void> _persistEtfs() async {
    await _cache.saveEtfs(etfs);
    notifyListeners();
    if (isSignedIn) {
      await _sheetsService.overwriteConfigRows(etfs.map((e) => e.toRow()).toList());
    }
  }

  Future<void> upsertInflationRate(InflationRate rate) async {
    final index = inflationRates.indexWhere((r) => r.year == rate.year);
    if (index >= 0) {
      inflationRates[index] = rate;
    } else {
      inflationRates.add(rate);
    }
    inflationRates.sort((a, b) => a.year.compareTo(b.year));
    await _cache.saveInflationRates(inflationRates);
    notifyListeners();
    if (isSignedIn) {
      await _sheetsService.overwriteInflationRows(inflationRates.map((r) => r.toRow()).toList());
    }
  }

  Future<void> addTransaction(InvestmentTransaction transaction) async {
    transactions.add(transaction);
    await _cache.saveTransactions(transactions);
    notifyListeners();
    if (isSignedIn) {
      await _sheetsService.appendTransactionRow(transaction.toRow());
    }
  }

  Future<void> setMonthlyBudget(double value) async {
    monthlyBudget = value;
    await _cache.setMonthlyBudget(value);
    notifyListeners();
  }

  Future<void> setMinOrderAmount(double value) async {
    minOrderAmount = value;
    await _cache.setMinOrderAmount(value);
    notifyListeners();
  }

  Future<void> setCommissionRatePct(double value) async {
    commissionRatePct = value;
    await _cache.setCommissionRatePct(value);
    notifyListeners();
  }

  Future<void> setReminderEnabled(bool value) async {
    reminderEnabled = value;
    await _cache.setReminderEnabled(value);
    notifyListeners();
  }

  Future<void> setReminderDay(int day) async {
    reminderDay = day;
    await _cache.setReminderDay(day);
    notifyListeners();
  }

  Future<void> setReminderTime({required int hour, required int minute}) async {
    reminderHour = hour;
    reminderMinute = minute;
    await _cache.setReminderTime(hour: hour, minute: minute);
    notifyListeners();
  }

  double investedIn(String isin) =>
      transactions.where((t) => t.isin == isin).fold(0, (sum, t) => sum + t.amountEur);

  double get totalInvested => transactions.fold(0, (sum, t) => sum + t.amountEur);

  List<EtfHolding> get holdings => etfs
      .map((etf) => EtfHolding(
            etf: etf,
            investedEur: investedIn(etf.isin),
            currentPrice: pricesByIsin[etf.isin],
          ))
      .toList();

  List<InvestmentTransaction> transactionsInMonth(DateTime month) => transactions
      .where((t) => t.date.year == month.year && t.date.month == month.month)
      .toList();

  /// What's left of this month's budget after transactions already made
  /// this calendar month — can go negative if more was spent than planned.
  double get budgetLeftThisMonth {
    final spent = transactionsInMonth(DateTime.now()).fold<double>(0, (sum, t) => sum + t.amountEur);
    return monthlyBudget - spent;
  }
}
