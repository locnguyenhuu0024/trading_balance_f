import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/exchange/exchange_models.dart';
import 'binance_cost_basis.dart';
import 'binance_market.dart';
import 'binance_private_client.dart';

/// Identifies a wallet and instrument independently of the account poll.
class BinanceCostSymbol {
  const BinanceCostSymbol(this.product, this.symbol, this.base, this.value);
  final String product, symbol, base;
  final double value;
  String get key => '$product:$symbol';
  bool get isMargin => product != 'Spot';
  bool get isIsolated => product == 'Isolated Margin';
}

class BinanceSymbolCost {
  const BinanceSymbolCost(
    this.cost, {
    this.completed = false,
    this.stale = false,
  });
  final CostState cost;
  final bool completed, stale;
}

class BinanceCostView {
  const BinanceCostView({
    this.symbols = const {},
    this.loading = false,
    this.available = true,
  });
  final Map<String, BinanceSymbolCost> symbols;
  final bool loading, available;
}

class BinanceCostStore {
  BinanceCostStore(this.preferences, String apiKey)
    : _prefix =
          'binance_cost_v1_${sha256.convert(utf8.encode(apiKey)).toString().substring(0, 16)}_';
  final SharedPreferences preferences;
  final String _prefix;
  static const prefix = 'binance_cost_v1_';

  BinanceSymbolCost? read(BinanceCostSymbol symbol) {
    final raw = preferences.getString('$_prefix${symbol.key}');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return BinanceSymbolCost(
        CostState.fromJson(json['cost'] as Map<String, dynamic>),
        completed: json['completed'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(BinanceCostSymbol symbol, BinanceSymbolCost state) async {
    await preferences.setString(
      '$_prefix${symbol.key}',
      jsonEncode({'cost': state.cost.toJson(), 'completed': state.completed}),
    );
  }

  static Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key
        in preferences
            .getKeys()
            .where((key) => key.startsWith(prefix))
            .toList()) {
      await preferences.remove(key);
    }
  }
}

/// Explicitly triggered by a screen; neither account reads nor polling start a run.
class BinanceCostController extends StateNotifier<BinanceCostView> {
  BinanceCostController(
    this.client,
    this.market,
    this.store, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(BinanceCostView(available: client.spotMarginAvailable));
  final BinancePrivateClient client;
  final BinanceMarket market;
  final BinanceCostStore store;
  final DateTime Function() _clock;
  DateTime? _lastRun;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> run(AccountSnapshot account) async {
    if (!client.spotMarginAvailable || state.loading || _disposed) return;
    final now = _clock();
    if (_lastRun != null &&
        now.difference(_lastRun!) < const Duration(seconds: 60))
      return;
    _lastRun = now;
    final generation = client.credentialState.value;
    bool cancelled() =>
        _disposed ||
        generation.rotating ||
        client.credentialState.value != generation;
    if (cancelled()) return;
    state = BinanceCostView(symbols: state.symbols, loading: true);
    var results = Map<String, BinanceSymbolCost>.from(state.symbols);
    try {
      final instruments = await market.instruments('SPOT');
      if (cancelled()) return;
      final candidates = <String, BinanceCostSymbol>{};
      void add(String product, String symbol, String base, double value) {
        final instrument = instruments[symbol];
        if (base == 'USDT' ||
            symbol != '${base}USDT' ||
            instrument?['base'] != base ||
            instrument?['quote'] != 'USDT')
          return;
        final item = BinanceCostSymbol(product, symbol, base, value.abs());
        candidates[item.key] = item;
      }

      for (final balance in account.balances) {
        if (balance.wallet == 'Spot' || balance.wallet == 'Cross Margin') {
          add(
            balance.wallet,
            '${balance.asset}USDT',
            balance.asset,
            double.tryParse(balance.valueUsdt ?? '') ?? 0,
          );
        }
      }
      for (final row in account.marginRows) {
        final key = row.key;
        if (key == null || key.base == null || key.quote != 'USDT') continue;
        final value =
            (double.tryParse(row.baseNet ?? '') ?? 0) *
            (double.tryParse(row.indexPrice ?? '') ?? 0);
        add('Isolated Margin', key.nativeId, key.base!, value);
      }
      final symbols = candidates.values.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      var pages = 0;
      for (final symbol in symbols.take(20)) {
        if (cancelled()) return;
        final old =
            store.read(symbol) ??
            BinanceSymbolCost(CostState(isMargin: symbol.isMargin));
        results[symbol.key] = old;
        if (pages >= 30) continue;
        var working = old.cost;
        try {
          var completed = false;
          while (pages < 30) {
            pages++;
            final response = await client.get(
              symbol.isMargin ? '/sapi/v1/margin/myTrades' : '/api/v3/myTrades',
              queryParameters: {
                'symbol': symbol.symbol,
                'limit': 1000,
                'fromId': (working.lastTradeId ?? -1) + 1,
                if (symbol.isIsolated) 'isIsolated': 'TRUE',
              },
            );
            if (cancelled()) return;
            final rows = response.data as List;
            var next = working;
            for (final raw in rows) {
              final row = raw as Map;
              final id = int.parse('${row['id']}');
              if (id <= (next.lastTradeId ?? -1))
                throw const FormatException('Unordered trades');
              if (row['isBuyer'] is! bool)
                throw const FormatException('Invalid trade side');
              next = next.apply(
                CostTrade(
                  id: id,
                  isBuyer: row['isBuyer'] as bool,
                  quantity: double.parse('${row['qty']}'),
                  quoteQuantity: double.parse('${row['quoteQty']}'),
                  commission: double.parse('${row['commission']}'),
                  commissionAsset: '${row['commissionAsset']}',
                  baseAsset: symbol.base,
                ),
              );
            }
            if (cancelled()) return;
            working = next;
            completed = rows.length < 1000;
            if (completed) break;
          }
          if (cancelled()) return;
          final updated = BinanceSymbolCost(working, completed: completed);
          await store.write(symbol, updated);
          if (cancelled()) return;
          results[symbol.key] = updated;
        } catch (error) {
          if (cancelled() ||
              (error is BinancePrivateException &&
                  error.failure.kind == ExchangeFailureKind.cancellation))
            return;
          results[symbol.key] = BinanceSymbolCost(
            old.cost,
            completed: old.completed,
            stale: true,
          );
          if (error is BinancePrivateException &&
              error.failure.kind == ExchangeFailureKind.credential)
            break;
        }
      }
    } catch (_) {
      // Instrument discovery is independent of the account read.
    } finally {
      if (!_disposed) {
        state = cancelled()
            ? const BinanceCostView()
            : BinanceCostView(symbols: results);
      }
    }
  }
}
