import '../../core/exchange/exchange_models.dart';
import 'binance_market.dart';
import 'binance_private_client.dart';

class BinanceReader {
  BinanceReader(this.client, this.market);
  final BinancePrivateClient client;
  final BinanceMarket market;

  String? _s(Object? value) => value?.toString();
  double _n(Object? value) => double.tryParse('$value') ?? 0;
  void _check(Object snapshot) {
    if (client.credentialState.value != snapshot ||
        client.credentialState.value.rotating) {
      throw const BinancePrivateException(
        ExchangeFailure(ExchangeFailureKind.cancellation),
      );
    }
  }

  Future<AccountSnapshot> readAccount() async {
    final generation = client.credentialState.value;
    _check(generation);
    final balances = <AssetBalance>[];
    final marginRows = <MarginAccountRow>[];
    final results = <WalletResult>[];
    final issues = <String>[];
    final pending = <(String, String, double, Map)>[];
    var credentialFailures = 0;
    final wallets = <(String, String)>[
      ('USD-M', '/fapi/v3/account'),
      if (client.spotMarginAvailable) ...[
        ('Spot', '/api/v3/account'),
        ('Cross Margin', '/sapi/v1/margin/account'),
        ('Isolated Margin', '/sapi/v1/margin/isolated/account'),
      ],
    ];
    for (final (name, path) in wallets) {
      try {
        final response = await client.get(
          path,
          queryParameters: name == 'Spot' ? {'omitZeroBalances': 'true'} : {},
        );
        _check(generation);
        final data = response.data as Map;
        results.add(WalletResult(wallet: name));
        if (name == 'USD-M') {
          for (final row in (data['assets'] as List? ?? [])) {
            final amount = _n(row['marginBalance']);
            if (amount != 0)
              pending.add((name, '${row['asset']}', amount, row));
          }
        } else if (name == 'Spot') {
          for (final row in (data['balances'] as List? ?? [])) {
            final amount = _n(row['free']) + _n(row['locked']);
            if (amount != 0)
              pending.add((name, '${row['asset']}', amount, row));
          }
        } else if (name == 'Cross Margin') {
          for (final row in (data['userAssets'] as List? ?? [])) {
            final amount = _n(row['netAsset']);
            if (amount == 0 && _n(row['borrowed']) == 0) continue;
            pending.add((name, '${row['asset']}', amount, row));
            marginRows.add(
              MarginAccountRow(
                asset: _s(row['asset']),
                net: _s(row['netAsset']),
                borrowed: _s(row['borrowed']),
                interest: _s(row['interest']),
                marginLevel: _s(data['marginLevel']),
              ),
            );
          }
        } else {
          for (final row in (data['assets'] as List? ?? [])) {
            final base = row['baseAsset'] as Map;
            final quote = row['quoteAsset'] as Map;
            if ([
              _n(base['netAsset']),
              _n(base['borrowed']),
              _n(quote['netAsset']),
              _n(quote['borrowed']),
            ].every((n) => n == 0))
              continue;
            for (final asset in [base, quote]) {
              final amount = _n(asset['netAsset']);
              if (amount != 0 || _n(asset['borrowed']) != 0)
                pending.add((name, '${asset['asset']}', amount, asset));
            }
            marginRows.add(
              MarginAccountRow(
                key: InstrumentKey(
                  exchange: ExchangeId.binance,
                  product: 'MARGIN',
                  nativeId: '${row['symbol']}',
                  base: _s(base['asset']),
                  quote: _s(quote['asset']),
                ),
                baseNet: _s(base['netAsset']),
                baseBorrowed: _s(base['borrowed']),
                baseInterest: _s(base['interest']),
                quoteNet: _s(quote['netAsset']),
                quoteBorrowed: _s(quote['borrowed']),
                quoteInterest: _s(quote['interest']),
                marginLevel: _s(row['marginLevel']),
                marginRatio: _s(row['marginRatio']),
                liquidation: _s(row['liquidatePrice']),
                indexPrice: _s(row['indexPrice']),
              ),
            );
          }
        }
      } on BinancePrivateException catch (e) {
        _check(generation);
        if (e.failure.kind == ExchangeFailureKind.cancellation) rethrow;
        if (e.failure.kind == ExchangeFailureKind.credential)
          credentialFailures++;
        results.add(WalletResult(wallet: name, available: false));
        issues.add('$name unavailable');
      }
    }
    if (credentialFailures == wallets.length) {
      throw const BinancePrivateException(
        ExchangeFailure(ExchangeFailureKind.credential),
      );
    }
    if (!client.spotMarginAvailable)
      issues.add('Spot and Margin are available in the app only');
    Map<String, double> prices = {};
    if (pending.any((row) => row.$2 != 'USDT' && row.$3 != 0)) {
      try {
        prices = await market.valuationPrices();
      } catch (_) {
        prices = {};
      }
    }
    _check(generation);
    var partial = results.any((r) => !r.available);
    var total = 0.0;
    for (final (wallet, asset, amount, row) in pending) {
      final price = asset == 'USDT' ? 1.0 : prices['${asset}USDT'];
      final value = amount == 0
          ? 0.0
          : price == null || price <= 0
          ? null
          : amount * price;
      if (value == null) {
        partial = true;
      } else {
        total += value;
      }
      balances.add(
        AssetBalance(
          wallet: wallet,
          asset: asset,
          total: wallet == 'Spot'
              ? amount.toString()
              : _s(row['marginBalance']),
          available: _s(row['free'] ?? row['availableBalance']),
          frozen: _s(row['locked']),
          borrowed: _s(row['borrowed']),
          interest: _s(row['interest']),
          net: _s(row['netAsset']),
          unrealizedPnl: _s(row['unrealizedProfit']),
          valueUsdt: value?.toStringAsFixed(2),
        ),
      );
    }
    return AccountSnapshot(
      total: total.toStringAsFixed(2),
      totalCurrency: 'USDT',
      isPartial: partial,
      balances: balances,
      marginRows: marginRows,
      walletResults: results,
      issues: issues,
    );
  }

  Future<List<ExchangePosition>> readPositions() async {
    final generation = client.credentialState.value;
    final risk = await client.get('/fapi/v3/positionRisk');
    final account = await client.get('/fapi/v2/account');
    final instruments = await market.instruments('SWAP');
    _check(generation);
    final details = (account.data['positions'] as List? ?? []);
    return [
      for (final row in risk.data as List)
        if (_n(row['positionAmt']) != 0)
          () {
            final match = details
                .where(
                  (p) =>
                      p['symbol'] == row['symbol'] &&
                      p['positionSide'] == row['positionSide'],
                )
                .firstOrNull;
            final symbol = '${row['symbol']}';
            final info = instruments[symbol];
            final isolated = match == null ? null : match['isolated'];
            return ExchangePosition(
              key: InstrumentKey(
                exchange: ExchangeId.binance,
                product: 'SWAP',
                nativeId: symbol,
                base: info?['base'],
                quote: info?['quote'],
              ),
              productLabel: 'SWAP',
              side: _s(row['positionSide']),
              size: _s(row['positionAmt']),
              entry: _s(row['entryPrice']),
              mark: _s(row['markPrice']),
              liquidation: _s(row['liquidationPrice']),
              leverage: _s(match?['leverage']),
              marginMode: isolated == null
                  ? null
                  : isolated == true || isolated == 'true'
                  ? 'isolated'
                  : 'cross',
              unrealizedPnl: _s(row['unRealizedProfit']),
              notional: _s(row['notional']),
              native: row,
            );
          }(),
    ];
  }

  Future<List<ExchangeOrder>> readOrders(String filter) async {
    final generation = client.credentialState.value;
    final orders = <ExchangeOrder>[];
    Future<void> load(
      String path,
      String product, [
      Map<String, dynamic> query = const {},
    ]) async {
      final response = await client.get(path, queryParameters: query);
      for (final row in response.data as List) {
        final symbol = '${row['symbol']}';
        orders.add(
          ExchangeOrder(
            id: '${row['orderId']}',
            key: InstrumentKey(
              exchange: ExchangeId.binance,
              product: product,
              nativeId: symbol,
            ),
            productLabel: product,
            type: _s(row['type']),
            side: _s(row['side']),
            price: _s(row['price']),
            quantity: _s(row['origQty']),
            filled: _s(row['executedQty']),
            state: _s(row['status']),
            createdAtMs: _s(row['time']),
            native: row,
          ),
        );
      }
    }

    if (filter == 'ALL' || filter == 'SWAP')
      await load('/fapi/v1/openOrders', 'SWAP');
    if (client.spotMarginAvailable && (filter == 'ALL' || filter == 'SPOT'))
      await load('/api/v3/openOrders', 'SPOT');
    if (client.spotMarginAvailable && (filter == 'ALL' || filter == 'MARGIN')) {
      await load('/sapi/v1/margin/openOrders', 'MARGIN');
      final account = await client.get('/sapi/v1/margin/isolated/account');
      for (final row in account.data['assets'] as List? ?? []) {
        final base = row['baseAsset'];
        final quote = row['quoteAsset'];
        if ([
          _n(base['netAsset']),
          _n(base['borrowed']),
          _n(quote['netAsset']),
          _n(quote['borrowed']),
        ].any((v) => v != 0)) {
          await load('/sapi/v1/margin/openOrders', 'MARGIN', {
            'symbol': row['symbol'],
            'isIsolated': 'TRUE',
          });
        }
      }
    }
    _check(generation);
    return orders;
  }

  Future<ExchangeOrderHistory> readHistory(
    String filter,
    List<String> symbols,
  ) async {
    final generation = client.credentialState.value;
    final coverage = symbols.toSet().take(10).toList();
    final orders = <ExchangeOrder>[];
    final issues = <String>[];
    final products = <(String, String)>[
      if (filter == 'ALL' || filter == 'SWAP') ('SWAP', '/fapi/v1/allOrders'),
      if (client.spotMarginAvailable && (filter == 'ALL' || filter == 'SPOT'))
        ('SPOT', '/api/v3/allOrders'),
      if (client.spotMarginAvailable && (filter == 'ALL' || filter == 'MARGIN'))
        ('MARGIN', '/sapi/v1/margin/allOrders'),
    ];
    for (final (product, path) in products) {
      for (final symbol in coverage) {
        try {
          final response = await client.get(
            path,
            queryParameters: {'symbol': symbol, 'limit': 100},
          );
          _check(generation);
          for (final row in response.data as List) {
            orders.add(
              ExchangeOrder(
                id: '${row['orderId']}',
                key: InstrumentKey(
                  exchange: ExchangeId.binance,
                  product: product,
                  nativeId: '${row['symbol']}',
                ),
                productLabel: product,
                type: _s(row['type']),
                side: _s(row['side']),
                price: _s(row['price']),
                quantity: _s(row['origQty']),
                filled: _s(row['executedQty']),
                state: _s(row['status']),
                createdAtMs: _s(row['time']),
                native: row,
              ),
            );
          }
        } catch (error) {
          _check(generation);
          if (error is BinancePrivateException &&
              error.failure.kind == ExchangeFailureKind.cancellation)
            rethrow;
          issues.add('$product $symbol unavailable');
        }
      }
    }
    _check(generation);
    orders.sort(
      (a, b) => (int.tryParse(b.createdAtMs ?? '') ?? 0).compareTo(
        int.tryParse(a.createdAtMs ?? '') ?? 0,
      ),
    );
    return ExchangeOrderHistory(
      orders: orders,
      symbols: coverage,
      issues: issues,
    );
  }
}
