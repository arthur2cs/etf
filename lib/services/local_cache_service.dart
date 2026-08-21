import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/etf.dart';
import '../models/inflation_rate.dart';
import '../models/investment_transaction.dart';

const _keyEtfs = 'cache_etfs';
const _keyTransactions = 'cache_transactions';
const _keyInflation = 'cache_inflation';
const _keyPrices = 'cache_prices';
const _keyPricesFetchedAt = 'cache_prices_fetched_at';

const _keyMonthlyBudget = 'settings_monthly_budget';
const _keyMinOrderAmount = 'settings_min_order_amount';
const _keyCommissionRatePct = 'settings_commission_rate_pct';
const _keyReminderEnabled = 'settings_reminder_enabled';
const _keyReminderDay = 'settings_reminder_day';
const _keyReminderHour = 'settings_reminder_hour';
const _keyReminderMinute = 'settings_reminder_minute';

/// Local on-device cache: lets the app show data instantly on launch and
/// keep working offline, while the Google Sheet stays the source of truth
/// that gets re-synced whenever the network is available.
class LocalCacheService {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> saveEtfs(List<Etf> etfs) async {
    final prefs = await _prefs;
    await prefs.setString(_keyEtfs, jsonEncode(etfs.map((e) => e.toJson()).toList()));
  }

  Future<List<Etf>> loadEtfs() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyEtfs);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Etf.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveTransactions(List<InvestmentTransaction> transactions) async {
    final prefs = await _prefs;
    await prefs.setString(
      _keyTransactions,
      jsonEncode(transactions.map((t) => t.toJson()).toList()),
    );
  }

  Future<List<InvestmentTransaction>> loadTransactions() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyTransactions);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((t) => InvestmentTransaction.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<void> saveInflationRates(List<InflationRate> rates) async {
    final prefs = await _prefs;
    await prefs.setString(_keyInflation, jsonEncode(rates.map((r) => r.toJson()).toList()));
  }

  Future<List<InflationRate>> loadInflationRates() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyInflation);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((r) => InflationRate.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> savePrices(Map<String, double> pricesByIsin) async {
    final prefs = await _prefs;
    await prefs.setString(_keyPrices, jsonEncode(pricesByIsin));
    await prefs.setString(_keyPricesFetchedAt, DateTime.now().toIso8601String());
  }

  Future<Map<String, double>> loadPrices() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyPrices);
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  Future<DateTime?> pricesFetchedAt() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyPricesFetchedAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<double> monthlyBudget() async => (await _prefs).getDouble(_keyMonthlyBudget) ?? 200;

  Future<void> setMonthlyBudget(double value) async => (await _prefs).setDouble(_keyMonthlyBudget, value);

  Future<double> minOrderAmount() async => (await _prefs).getDouble(_keyMinOrderAmount) ?? 200;

  Future<void> setMinOrderAmount(double value) async =>
      (await _prefs).setDouble(_keyMinOrderAmount, value);

  /// BoursoBank commission, as a % of the gross order amount (e.g. 0.5 for
  /// 0.5%). Deduced from the user's own past orders — see README.
  Future<double> commissionRatePct() async =>
      (await _prefs).getDouble(_keyCommissionRatePct) ?? 0.5;

  Future<void> setCommissionRatePct(double value) async =>
      (await _prefs).setDouble(_keyCommissionRatePct, value);

  Future<bool> reminderEnabled() async => (await _prefs).getBool(_keyReminderEnabled) ?? true;

  Future<void> setReminderEnabled(bool value) async => (await _prefs).setBool(_keyReminderEnabled, value);

  Future<int> reminderDay() async => (await _prefs).getInt(_keyReminderDay) ?? 1;

  Future<void> setReminderDay(int day) async => (await _prefs).setInt(_keyReminderDay, day);

  Future<int> reminderHour() async => (await _prefs).getInt(_keyReminderHour) ?? 9;

  Future<int> reminderMinute() async => (await _prefs).getInt(_keyReminderMinute) ?? 0;

  Future<void> setReminderTime({required int hour, required int minute}) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyReminderHour, hour);
    await prefs.setInt(_keyReminderMinute, minute);
  }
}
