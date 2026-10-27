import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/binance_data_client.dart';
import '../network/binance_request_coordinator.dart';
import '../security/secure_storage_helper.dart';
import 'binance_read_routes.dart';
import 'exchange_models.dart';
import 'exchange_readers.dart';

typedef BinanceExchangeReaderClock = DateTime Function();

final binanceExchangeReaderProvider = Provider<BinanceExchangeReader>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final reader = BinanceExchangeReader(
    client: ref.watch(binanceDataClientProvider),
    credentialState: storage.binanceCredentialState,
    requestCoordinator: ref.watch(binanceRequestCoordinatorProvider),
  );
  ref.onDispose(reader.dispose);
  return reader;
});

/// Source-native Binance account and order reader. All private reads remain
/// generation checked by both this adapter and the guarded transport.
class BinanceExchangeReader implements ExchangeReader {
  static const Duration _spotPortfolioCatalogLifetime = Duration(minutes: 60);

  BinanceExchangeReader({
    required BinanceDataClient client,
    required ValueListenable<BinanceCredentialSnapshot> credentialState,
    required BinanceRequestCoordinator requestCoordinator,
    BinanceExchangeReaderClock? clock,
  }) : _client = client,
       credentialState = credentialState,
       requestCoordinator = requestCoordinator,
       _clock = clock ?? DateTime.now {
    _observedSnapshot = credentialState.value;
    credentialState.addListener(_onCredentialStateChanged);
  }

  final BinanceDataClient _client;
  final BinanceExchangeReaderClock _clock;
  final BinanceRequestCoordinator requestCoordinator;
  final ValueListenable<BinanceCredentialSnapshot> credentialState;
  final Map<ExchangeProduct, Map<String, ExchangeInstrument>>
  _knownInstruments = <ExchangeProduct, Map<String, ExchangeInstrument>>{};
  late BinanceCredentialSnapshot _observedSnapshot;
  Future<ExchangeValue<String>>? _multiAssetMode;
  int? _spotCatalogGeneration;
  int? _futuresCatalogGeneration;
  ExchangeCatalog? _storedSpotCatalog;
  int? _storedSpotCatalogGeneration;
  DateTime? _storedSpotCatalogFetchedAt;
  bool _disposed = false;

  @override
  ExchangeSource get source => ExchangeSource.binance;

  int get generation => credentialState.value.generation;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    credentialState.removeListener(_onCredentialStateChanged);
    _knownInstruments.clear();
    _multiAssetMode = null;
    _clearStoredSpotCatalog();
  }

  void rememberSpotSymbols(
    Iterable<String> symbols, {
    required BinanceCredentialSnapshot snapshot,
  }) => _rememberSymbols(ExchangeProduct.spot, symbols, snapshot);

  void rememberFuturesSymbols(
    Iterable<String> symbols, {
    required BinanceCredentialSnapshot snapshot,
  }) => _rememberSymbols(ExchangeProduct.swap, symbols, snapshot);

  Future<ExchangeCatalog> getSpotCatalog({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
    Iterable<String> knownSymbols = const <String>[],
    bool reuseForPortfolio = false,
  }) async {
    final snapshot = _captureSnapshot(expectedGeneration);
    final symbols = reuseForPortfolio
        ? knownSymbols.toList(growable: false)
        : knownSymbols;
    if (reuseForPortfolio && symbols.isEmpty) {
      final catalog = _storedSpotCatalog;
      final fetchedAt = _storedSpotCatalogFetchedAt;
      if (catalog != null &&
          fetchedAt != null &&
          _storedSpotCatalogGeneration == snapshot.generation) {
        final age = now().difference(fetchedAt);
        if (!age.isNegative && age < _spotPortfolioCatalogLifetime) {
          _assertCurrent(snapshot);
          return catalog;
        }
      }
    }
    final response = await _get(
      '/api/v3/exchangeInfo',
      cancelToken: cancelToken,
      priority: BinanceRequestPriority.bootstrap,
    );
    _assertCurrent(snapshot);
    final body = _asStringKeyedMap(response.data);
    final rows = body?['symbols'];
    if (rows is! List) {
      throw const ExchangeReadException(
        code: 'binance_invalid_catalog',
        message: 'Binance returned an invalid Spot catalog.',
      );
    }

    final instruments = <String, ExchangeInstrument>{};
    final issues = <ExchangeReadIssue>[];
    for (var index = 0; index < rows.length; index++) {
      final row = _asStringKeyedMap(rows[index]);
      if (row == null) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_invalid_catalog_row',
            message: 'A Spot catalog row was not an object.',
          ),
        );
        continue;
      }
      final enabled = row['isSpotTradingAllowed'];
      if (enabled == false) continue;
      if (enabled != true) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_spot_enabled_unknown',
            message: 'Spot-enabled status was unavailable for a catalog row.',
          ),
        );
        continue;
      }
      final symbol = _validInstrumentSymbol(row['symbol']);
      if (symbol == null) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_invalid_spot_symbol',
            message: 'A Spot-enabled catalog row had no usable symbol.',
          ),
        );
        continue;
      }
      final base = _assetValue(row['baseAsset']);
      final quote = _assetValue(row['quoteAsset']);
      if (!base.isAvailable || !quote.isAvailable) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_invalid_spot_instrument',
            message: 'Spot instrument metadata was incomplete.',
            instrument: symbol,
          ),
        );
      }
      instruments[symbol] = ExchangeInstrument(
        source: ExchangeSource.binance,
        product: ExchangeProduct.spot,
        symbol: symbol,
        baseAsset: base,
        quoteAsset: quote,
        settlementAsset: quote,
        status: _optionalString(row['status']),
        nativeRecord: row,
      );
    }

    final remembered = _knownInstruments.putIfAbsent(
      ExchangeProduct.spot,
      () => <String, ExchangeInstrument>{},
    );
    remembered.addAll(instruments);
    _rememberSymbols(ExchangeProduct.spot, symbols, snapshot);
    for (final symbol in remembered.keys) {
      instruments.putIfAbsent(symbol, () => remembered[symbol]!);
    }
    _assertCurrent(snapshot);
    final catalog = ExchangeCatalog(
      source: ExchangeSource.binance,
      product: ExchangeProduct.spot,
      generation: snapshot.generation,
      instruments: instruments.values.toList()
        ..sort((left, right) => left.symbol.compareTo(right.symbol)),
      issues: issues,
    );
    _spotCatalogGeneration = snapshot.generation;
    _storedSpotCatalog = catalog;
    _storedSpotCatalogGeneration = snapshot.generation;
    _storedSpotCatalogFetchedAt = now();
    return catalog;
  }

  Future<ExchangeCatalog> getFuturesCatalog({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
    Iterable<String> knownSymbols = const <String>[],
  }) async {
    final snapshot = _captureSnapshot(expectedGeneration);
    final response = await _get(
      '/fapi/v1/exchangeInfo',
      cancelToken: cancelToken,
      priority: BinanceRequestPriority.bootstrap,
    );
    _assertCurrent(snapshot);
    final body = _asStringKeyedMap(response.data);
    final rows = body?['symbols'];
    if (rows is! List) {
      throw const ExchangeReadException(
        code: 'binance_invalid_catalog',
        message: 'Binance returned an invalid Futures catalog.',
      );
    }

    final instruments = <String, ExchangeInstrument>{};
    final issues = <ExchangeReadIssue>[];
    for (final value in rows) {
      final row = _asStringKeyedMap(value);
      if (row == null) {
        issues.add(
          const ExchangeReadIssue(
            code: 'binance_invalid_catalog_row',
            message: 'A Futures catalog row was not an object.',
          ),
        );
        continue;
      }
      final settlement = _assetValue(row['marginAsset']);
      final symbol = _validInstrumentSymbol(row['symbol']);
      if (!settlement.isAvailable) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_contract_settlement_unknown',
            message:
                'Settlement asset was unavailable for a Futures catalog row.',
            instrument: symbol,
          ),
        );
        continue;
      }
      if (settlement.value != 'USDT') continue;
      final contractType = _optionalString(row['contractType']);
      final product = _futuresProduct(contractType);
      if (symbol == null || product == null) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_invalid_usdt_contract',
            message:
                'A USDT-settled contract had incomplete identity metadata.',
            instrument: symbol,
          ),
        );
        continue;
      }
      final quote = _assetValue(row['quoteAsset']);
      instruments[symbol] = ExchangeInstrument(
        source: ExchangeSource.binance,
        product: product,
        symbol: symbol,
        baseAsset: _assetValue(row['baseAsset']),
        quoteAsset: quote,
        settlementAsset: settlement,
        status: _optionalString(row['status']),
        contractType: contractType,
        nativeRecord: row,
      );
      if (!quote.isAvailable) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_contract_quote_unknown',
            message: 'Contract quote asset was unavailable.',
            instrument: symbol,
          ),
        );
      }
    }

    final remembered = _knownInstruments.putIfAbsent(
      ExchangeProduct.swap,
      () => <String, ExchangeInstrument>{},
    );
    remembered.addAll(instruments);
    _rememberSymbols(ExchangeProduct.swap, knownSymbols, snapshot);
    for (final symbol in remembered.keys) {
      final instrument = remembered[symbol]!;
      if (instrument.settlementAsset.value != 'USDT') {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_futures_known_symbol_metadata_unavailable',
            message:
                'A remembered Futures symbol is excluded until its USDT settlement is established.',
            instrument: symbol,
          ),
        );
        continue;
      }
      instruments.putIfAbsent(symbol, () => instrument);
    }
    _assertCurrent(snapshot);
    final list = instruments.values.toList()
      ..sort((left, right) => left.symbol.compareTo(right.symbol));
    final catalog = ExchangeCatalog(
      source: ExchangeSource.binance,
      product: ExchangeProduct.swap,
      generation: snapshot.generation,
      instruments: list,
      issues: issues,
    );
    _futuresCatalogGeneration = snapshot.generation;
    return catalog;
  }

  Future<ExchangeAccountSnapshot> getSpotAccount({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    final snapshot = _captureSnapshot(expectedGeneration, requireUsable: true);
    await _ensureSpotCatalog(snapshot, cancelToken);
    final response = await _get(
      '/api/v3/account',
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
      requireUsable: true,
    );
    _assertCurrent(snapshot, requireUsable: true);
    final body = _asStringKeyedMap(response.data);
    final rawBalances = body?['balances'];
    if (rawBalances is! List) {
      throw const ExchangeReadException(
        code: 'binance_invalid_account',
        message: 'Binance returned an invalid Spot account response.',
      );
    }
    final balances = <ExchangeBalance>[];
    final issues = <ExchangeReadIssue>[];
    for (final value in rawBalances) {
      final row = _asStringKeyedMap(value);
      if (row == null) {
        issues.add(
          const ExchangeReadIssue(
            code: 'binance_invalid_balance_row',
            message: 'A Spot balance row was not an object.',
          ),
        );
        continue;
      }
      final asset = _assetCode(row['asset']);
      if (asset == null) {
        issues.add(
          const ExchangeReadIssue(
            code: 'binance_invalid_balance_asset',
            message: 'A Spot balance asset was unavailable.',
          ),
        );
        continue;
      }
      final free = _amountValue(row['free'], 'Spot free balance');
      final locked = _amountValue(row['locked'], 'Spot locked balance');
      if (!free.isAvailable || !locked.isAvailable) {
        issues.add(
          ExchangeReadIssue(
            code: 'binance_invalid_balance_amount',
            message: 'A Spot free or locked balance was unavailable.',
            instrument: asset,
          ),
        );
      }
      balances.add(
        ExchangeBalance(
          source: ExchangeSource.binance,
          product: ExchangeProduct.spot,
          wallet: 'spot',
          asset: asset,
          free: free,
          locked: locked,
        ),
      );
    }
    return ExchangeAccountSnapshot(
      source: ExchangeSource.binance,
      product: ExchangeProduct.spot,
      generation: snapshot.generation,
      balances: balances,
      reportedEquity: const ExchangeValue.unavailable(
        'Spot equity requires fresh Binance Spot valuation quotes.',
      ),
      unrealizedPnl: const ExchangeValue.unavailable(
        'Spot account does not report futures unrealized PnL.',
      ),
      equityIncludesUnrealizedPnl: false,
      issues: issues,
      nativeRecord: body,
    );
  }

  Future<ExchangeAccountSnapshot> getFuturesAccount({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    final snapshot = _captureSnapshot(expectedGeneration, requireUsable: true);
    await _ensureFuturesCatalog(snapshot, cancelToken);
    final issues = <ExchangeReadIssue>[];
    late final ExchangeValue<String> accountMode;
    try {
      accountMode = await _multiAssetsMode(snapshot, cancelToken);
    } on ExchangeReadException catch (error) {
      if (_isControlFlowFailure(error) || _isAuthenticationFailure(error)) {
        rethrow;
      }
      accountMode = ExchangeValue<String>.unavailable(
        'Futures account mode could not be read: ' + error.code + '.',
      );
      issues.add(
        const ExchangeReadIssue(
          code: 'binance_futures_account_mode_unavailable',
          message: 'Futures account denomination could not be determined.',
        ),
      );
    }
    final response = await _get(
      '/fapi/v3/account',
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
      requireUsable: true,
    );
    _assertCurrent(snapshot, requireUsable: true);
    final body = _asStringKeyedMap(response.data);
    if (body == null) {
      throw const ExchangeReadException(
        code: 'binance_invalid_account',
        message: 'Binance returned an invalid Futures account response.',
      );
    }

    final currency = switch (accountMode.value) {
      'multi_asset' => 'USD',
      'single_asset' => 'USDT',
      _ => null,
    };
    final equity = currency == null
        ? ExchangeValue<ExchangeMoney>.unavailable(
            accountMode.reason ??
                'Futures account denomination is unavailable.',
          )
        : _moneyValue(
            body['totalMarginBalance'],
            currency,
            'Futures margin equity',
          );
    final pnl = currency == null
        ? ExchangeValue<ExchangeMoney>.unavailable(
            accountMode.reason ??
                'Futures account denomination is unavailable.',
          )
        : _moneyValue(
            body['totalUnrealizedProfit'],
            currency,
            'Futures unrealized PnL',
          );

    final assetsValue = body['assets'];
    final balances = <ExchangeBalance>[];
    if (assetsValue is List) {
      for (final value in assetsValue) {
        final row = _asStringKeyedMap(value);
        final asset = _assetCode(row?['asset']);
        if (row == null || asset == null) {
          issues.add(
            const ExchangeReadIssue(
              code: 'binance_invalid_futures_balance',
              message: 'A Futures wallet balance row was unavailable.',
            ),
          );
          continue;
        }
        balances.add(
          ExchangeBalance(
            source: ExchangeSource.binance,
            product: ExchangeProduct.futures,
            wallet: 'futures',
            asset: asset,
            free: _amountValue(
              row['availableBalance'],
              'Futures available balance',
            ),
            locked: const ExchangeValue.unavailable(
              'Binance does not report a separate locked Futures wallet amount.',
            ),
            reportedTotal: _amountValue(
              row['walletBalance'],
              'Futures wallet balance',
            ),
            nativeRecord: row,
          ),
        );
      }
    } else {
      issues.add(
        const ExchangeReadIssue(
          code: 'binance_futures_assets_unavailable',
          message: 'Futures wallet asset details were unavailable.',
        ),
      );
    }
    if (!equity.isAvailable) {
      issues.add(
        const ExchangeReadIssue(
          code: 'binance_futures_equity_unavailable',
          message: 'Native Futures margin equity was unavailable.',
        ),
      );
    }
    List<ExchangePosition> positions = const <ExchangePosition>[];
    try {
      positions = await getFuturesPositions(
        cancelToken: cancelToken,
        expectedGeneration: snapshot,
        issues: issues,
      );
    } on ExchangeReadException catch (error) {
      if (_isControlFlowFailure(error)) rethrow;
      issues.add(
        const ExchangeReadIssue(
          code: 'binance_futures_positions_unavailable',
          message:
              'Native Futures equity loaded, but position details were unavailable.',
        ),
      );
    }
    _assertCurrent(snapshot, requireUsable: true);
    _assertRequestActive(snapshot, cancelToken);
    return ExchangeAccountSnapshot(
      source: ExchangeSource.binance,
      product: ExchangeProduct.futures,
      generation: snapshot.generation,
      accountMode: accountMode.value,
      balances: balances,
      reportedEquity: equity,
      unrealizedPnl: pnl,
      equityIncludesUnrealizedPnl: true,
      positions: positions,
      issues: issues,
      nativeRecord: body,
    );
  }

  Future<List<ExchangePosition>> getFuturesPositions({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
    List<ExchangeReadIssue>? issues,
  }) async {
    final snapshot = _captureSnapshot(expectedGeneration, requireUsable: true);
    await _ensureFuturesCatalog(snapshot, cancelToken);
    final riskResponse = await _get(
      '/fapi/v3/positionRisk',
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
      requireUsable: true,
    );
    _assertCurrent(snapshot, requireUsable: true);
    final riskRows = _asList(riskResponse.data);
    if (riskRows == null) {
      throw const ExchangeReadException(
        code: 'binance_invalid_positions',
        message: 'Binance returned invalid Futures positions.',
      );
    }
    List<Object?> configRows = const <Object?>[];
    try {
      final configResponse = await _get(
        '/fapi/v1/symbolConfig',
        cancelToken: cancelToken,
        expectedGeneration: snapshot,
        requireUsable: true,
      );
      configRows = _asList(configResponse.data) ?? const <Object?>[];
      if (configRows.isEmpty) {
        issues?.add(
          const ExchangeReadIssue(
            code: 'binance_symbol_config_unavailable',
            message: 'Position leverage or margin mode may be unavailable.',
          ),
        );
      }
    } on ExchangeReadException catch (error) {
      if (_isControlFlowFailure(error)) rethrow;
      issues?.add(
        const ExchangeReadIssue(
          code: 'binance_symbol_config_unavailable',
          message: 'Position leverage or margin mode may be unavailable.',
        ),
      );
    }
    final configs = <String, Map<String, dynamic>>{};
    for (final value in configRows) {
      final config = _asStringKeyedMap(value);
      final symbol = _validInstrumentSymbol(config?['symbol']);
      if (config != null && symbol != null) configs[symbol] = config;
    }
    final results = <ExchangePosition>[];
    for (final value in riskRows) {
      final row = _asStringKeyedMap(value);
      final symbol = _validInstrumentSymbol(row?['symbol']);
      final amount = ExchangeAmount.tryParse(row?['positionAmt']);
      if (row == null || symbol == null || amount == null) {
        issues?.add(
          const ExchangeReadIssue(
            code: 'binance_invalid_position',
            message: 'A Futures position row had invalid identity or quantity.',
          ),
        );
        continue;
      }
      if (amount.isZero) continue;
      final positionSide = _optionalString(row['positionSide'])?.toUpperCase();
      final side = switch (positionSide) {
        'LONG' => ExchangePositionSide.long,
        'SHORT' => ExchangePositionSide.short,
        'BOTH' => ExchangePositionSide.net,
        _ => ExchangePositionSide.unknown,
      };
      final config = configs[symbol];
      final knownInstrument = _knownFuturesInstrument(symbol);
      final marginAsset = _assetValue(
        row['marginAsset'] ?? knownInstrument?.settlementAsset.value,
      );
      if (marginAsset.value != 'USDT') {
        issues?.add(
          ExchangeReadIssue(
            code: 'binance_non_usdt_or_unknown_position',
            message:
                'Position was excluded because its USDT settlement was not established.',
            instrument: symbol,
          ),
        );
        continue;
      }
      final product =
          knownInstrument?.product ??
          _futuresProduct(_optionalString(row['contractType']));
      if (product == null || side == ExchangePositionSide.unknown) {
        issues?.add(
          ExchangeReadIssue(
            code: 'binance_position_metadata_unknown',
            message: 'Position product or side metadata was unavailable.',
            instrument: symbol,
          ),
        );
      }
      results.add(
        ExchangePosition(
          source: ExchangeSource.binance,
          product: product,
          symbol: symbol,
          side: side,
          positionAmount: ExchangeValue.available(amount),
          entryPrice: _amountValue(row['entryPrice'], 'Futures entry price'),
          markPrice: _amountValue(row['markPrice'], 'Futures mark price'),
          unrealizedPnl: _moneyValue(
            row['unRealizedProfit'],
            marginAsset.value,
            'Futures position unrealized PnL',
          ),
          marginMode: _stringValue(config?['marginType'], 'margin mode'),
          leverage: _amountValue(config?['leverage'], 'leverage'),
          marginCurrency: marginAsset,
          nativeId: _optionalString(row['positionSide']),
          nativeRecord: row,
        ),
      );
    }
    results.sort(
      (left, right) => left.identityKey.compareTo(right.identityKey),
    );
    _assertRequestActive(snapshot, cancelToken);
    return List<ExchangePosition>.unmodifiable(results);
  }

  Future<List<ExchangeOrder>> getSpotOpenOrders({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    final snapshot = _captureSnapshot(expectedGeneration, requireUsable: true);
    await _ensureSpotCatalog(snapshot, cancelToken);
    final response = await _get(
      '/api/v3/openOrders',
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
      requireUsable: true,
    );
    _assertCurrent(snapshot, requireUsable: true);
    final rows = _asList(response.data);
    if (rows == null) throw _invalidRows('Spot open orders');
    final orders = rows
        .map((row) => _spotOrder(row, kind: ExchangeOrderKind.ordinary))
        .toList(growable: false);
    rememberSpotSymbols(
      orders.map((order) => order.symbol),
      snapshot: snapshot,
    );
    return List<ExchangeOrder>.unmodifiable(orders);
  }

  Future<List<ExchangeOrder>> getFuturesOpenOrders({
    CancelToken? cancelToken,
    BinanceCredentialSnapshot? expectedGeneration,
  }) async {
    final snapshot = _captureSnapshot(expectedGeneration, requireUsable: true);
    await _ensureFuturesCatalog(snapshot, cancelToken);
    final ordinaryResponse = await _get(
      '/fapi/v1/openOrders',
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
      requireUsable: true,
    );
    final conditionalResponse = await _get(
      '/fapi/v1/openAlgoOrders',
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
      requireUsable: true,
    );
    _assertCurrent(snapshot, requireUsable: true);
    final ordinaryRows = _asList(ordinaryResponse.data);
    final conditionalRows = _asList(conditionalResponse.data);
    if (ordinaryRows == null || conditionalRows == null) {
      throw _invalidRows('Futures open orders');
    }
    final orders = linkConditionalExecutions(<ExchangeOrder>[
      ...ordinaryRows.map(
        (row) => _futuresOrder(row, kind: ExchangeOrderKind.ordinary),
      ),
      ...conditionalRows.map(
        (row) => _futuresOrder(row, kind: ExchangeOrderKind.conditional),
      ),
    ]);
    rememberFuturesSymbols(
      orders.map((order) => order.symbol),
      snapshot: snapshot,
    );
    return List<ExchangeOrder>.unmodifiable(orders);
  }

  Future<List<ExchangeOrder>> readSpotHistoryPage(
    ExchangeInstrument instrument, {
    required BinanceCredentialSnapshot expectedGeneration,
    required CancelToken cancelToken,
  }) async {
    _assertInstrument(instrument, ExchangeProduct.spot);
    final response = await _get(
      '/api/v3/allOrders',
      queryParameters: <String, dynamic>{
        'symbol': instrument.symbol,
        'limit': 500,
      },
      cancelToken: cancelToken,
      priority: BinanceRequestPriority.history,
      expectedGeneration: expectedGeneration,
      requireUsable: true,
    );
    _assertCurrent(expectedGeneration, requireUsable: true);
    final rows = _asList(response.data);
    if (rows == null) throw _invalidRows('Spot order history');
    return List<ExchangeOrder>.unmodifiable(
      rows.map((row) => _spotOrder(row, kind: ExchangeOrderKind.ordinary)),
    );
  }

  Future<List<ExchangeOrder>> readFuturesHistoryPage(
    ExchangeInstrument instrument, {
    required ExchangeOrderKind kind,
    required BinanceCredentialSnapshot expectedGeneration,
    required CancelToken cancelToken,
  }) async {
    _assertFuturesInstrument(instrument);
    final path = kind == ExchangeOrderKind.ordinary
        ? '/fapi/v1/allOrders'
        : '/fapi/v1/allAlgoOrders';
    final response = await _get(
      path,
      queryParameters: <String, dynamic>{
        'symbol': instrument.symbol,
        'limit': 500,
      },
      cancelToken: cancelToken,
      priority: BinanceRequestPriority.history,
      expectedGeneration: expectedGeneration,
      requireUsable: true,
    );
    _assertCurrent(expectedGeneration, requireUsable: true);
    final rows = _asList(response.data);
    if (rows == null) throw _invalidRows('Futures order history');
    return List<ExchangeOrder>.unmodifiable(
      rows.map(
        (row) =>
            _futuresOrder(row, kind: kind, fallbackProduct: instrument.product),
      ),
    );
  }

  Future<ExchangeValue<String>> _multiAssetsMode(
    BinanceCredentialSnapshot snapshot,
    CancelToken? cancelToken,
  ) async {
    _assertCurrent(snapshot, requireUsable: true);
    final cached = _multiAssetMode;
    if (cached != null) return cached;
    final future = () async {
      final response = await _get(
        '/fapi/v1/multiAssetsMargin',
        cancelToken: cancelToken,
        expectedGeneration: snapshot,
        requireUsable: true,
      );
      _assertCurrent(snapshot, requireUsable: true);
      final body = _asStringKeyedMap(response.data);
      return switch (body?['multiAssetsMargin']) {
        true => const ExchangeValue<String>.available('multi_asset'),
        false => const ExchangeValue<String>.available('single_asset'),
        _ => const ExchangeValue<String>.unavailable(
          'Futures account mode was unavailable.',
        ),
      };
    }();
    _multiAssetMode = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_multiAssetMode, future)) _multiAssetMode = null;
      rethrow;
    }
  }

  Future<void> _ensureSpotCatalog(
    BinanceCredentialSnapshot snapshot,
    CancelToken? cancelToken,
  ) async {
    if (_spotCatalogGeneration == snapshot.generation) return;
    await getSpotCatalog(
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
    );
  }

  Future<void> _ensureFuturesCatalog(
    BinanceCredentialSnapshot snapshot,
    CancelToken? cancelToken,
  ) async {
    if (_futuresCatalogGeneration == snapshot.generation) return;
    await getFuturesCatalog(
      cancelToken: cancelToken,
      expectedGeneration: snapshot,
    );
  }

  Future<Response<dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    BinanceRequestPriority priority = BinanceRequestPriority.interactive,
    BinanceCredentialSnapshot? expectedGeneration,
    bool requireUsable = false,
  }) async {
    _assertNotDisposed();
    final snapshot = expectedGeneration ?? credentialState.value;
    if (requireUsable) _assertCurrent(snapshot, requireUsable: true);
    try {
      final response = await _client.get(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        priority: priority,
      );
      if (cancelToken?.isCancelled ?? false) {
        throw const ExchangeReadException(
          code: 'request_cancelled',
          message: 'The Binance read request was cancelled.',
        );
      }
      if (expectedGeneration != null) {
        _assertCurrent(expectedGeneration, requireUsable: requireUsable);
      }
      return response;
    } on BinanceDataException catch (error) {
      throw ExchangeReadException(
        code: error.code,
        message: error.message,
        retryAt: error.retryAt,
        statusCode: error.statusCode,
      );
    }
  }

  void _assertInstrument(
    ExchangeInstrument instrument,
    ExchangeProduct product,
  ) {
    final validProduct = product == ExchangeProduct.spot
        ? instrument.product == ExchangeProduct.spot
        : instrument.product == null ||
              instrument.product == ExchangeProduct.swap ||
              instrument.product == ExchangeProduct.futures;
    if (instrument.source != ExchangeSource.binance ||
        !validProduct ||
        _validInstrumentSymbol(instrument.symbol) == null) {
      throw const ExchangeReadException(
        code: 'binance_invalid_history_instrument',
        message: 'The requested Binance history instrument is invalid.',
      );
    }
  }

  void _assertFuturesInstrument(ExchangeInstrument instrument) {
    if (instrument.source != ExchangeSource.binance ||
        (instrument.product != null &&
            instrument.product != ExchangeProduct.swap &&
            instrument.product != ExchangeProduct.futures) ||
        _validInstrumentSymbol(instrument.symbol) == null ||
        instrument.settlementAsset.value != 'USDT') {
      throw const ExchangeReadException(
        code: 'binance_invalid_history_instrument',
        message: 'The requested Binance Futures history instrument is invalid.',
      );
    }
  }

  void _rememberSymbols(
    ExchangeProduct product,
    Iterable<String> symbols,
    BinanceCredentialSnapshot snapshot,
  ) {
    _assertCurrent(snapshot);
    final remembered = _knownInstruments.putIfAbsent(
      product,
      () => <String, ExchangeInstrument>{},
    );
    for (final rawSymbol in symbols) {
      final symbol = _validInstrumentSymbol(rawSymbol);
      if (symbol == null) continue;
      remembered.putIfAbsent(
        symbol,
        () => ExchangeInstrument(
          source: ExchangeSource.binance,
          product: product == ExchangeProduct.swap ? null : product,
          symbol: symbol,
          baseAsset: const ExchangeValue.unavailable(
            'Instrument metadata was not provided in this generation.',
          ),
          quoteAsset: const ExchangeValue.unavailable(
            'Instrument metadata was not provided in this generation.',
          ),
          settlementAsset: const ExchangeValue.unavailable(
            'Instrument settlement metadata was not provided.',
          ),
        ),
      );
    }
  }

  BinanceCredentialSnapshot _captureSnapshot(
    BinanceCredentialSnapshot? expected, {
    bool requireUsable = false,
  }) {
    _assertNotDisposed();
    final current = credentialState.value;
    if (expected != null && current != expected) {
      throw const ExchangeReadException(
        code: 'binance_credential_generation_changed',
        message: 'The Binance credential generation changed.',
      );
    }
    if (requireUsable && !current.canUsePrivateReads) {
      throw const ExchangeReadException(
        code: 'binance_credentials_unavailable',
        message: 'Binance private reads are unavailable for this generation.',
      );
    }
    return current;
  }

  void _assertCurrent(
    BinanceCredentialSnapshot expected, {
    bool requireUsable = false,
  }) {
    _assertNotDisposed();
    final current = credentialState.value;
    if (current != expected || (requireUsable && !current.canUsePrivateReads)) {
      throw const ExchangeReadException(
        code: 'binance_credential_generation_changed',
        message: 'The Binance credential generation changed during the read.',
      );
    }
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw const ExchangeReadException(
        code: 'binance_reader_disposed',
        message: 'The Binance reader is no longer active.',
      );
    }
  }

  void _assertRequestActive(
    BinanceCredentialSnapshot snapshot,
    CancelToken? cancelToken,
  ) {
    _assertCurrent(snapshot, requireUsable: true);
    if (cancelToken?.isCancelled ?? false) {
      throw const ExchangeReadException(
        code: 'request_cancelled',
        message: 'The Binance read request was cancelled.',
      );
    }
  }

  static bool _isControlFlowFailure(ExchangeReadException error) =>
      error.code == 'request_cancelled' ||
      error.code == 'binance_request_cancelled' ||
      error.code == 'binance_credential_generation_changed' ||
      error.code == 'binance_credentials_unavailable' ||
      error.code == 'binance_reader_disposed' ||
      error.code == 'binance_budget_metadata_unavailable' ||
      error.code == 'binance_host_paused' ||
      error.code == 'binance_rate_limited' ||
      error.code == 'binance_ip_banned';

  static bool _isAuthenticationFailure(ExchangeReadException error) =>
      error.code == 'binance_authentication_failed' ||
      error.code == 'binance_credentials_required' ||
      (error.code == 'binance_http_error' &&
          (error.statusCode == 401 || error.statusCode == 403));

  void _onCredentialStateChanged() {
    final current = credentialState.value;
    if (current.generation == _observedSnapshot.generation) {
      _observedSnapshot = current;
      return;
    }
    _observedSnapshot = current;
    _knownInstruments.clear();
    _multiAssetMode = null;
    _spotCatalogGeneration = null;
    _futuresCatalogGeneration = null;
    _clearStoredSpotCatalog();
  }

  void _clearStoredSpotCatalog() {
    _storedSpotCatalog = null;
    _storedSpotCatalogGeneration = null;
    _storedSpotCatalogFetchedAt = null;
  }

  ExchangeOrder _spotOrder(Object? value, {required ExchangeOrderKind kind}) {
    final row = _asStringKeyedMap(value);
    if (row == null) throw _invalidRows('Spot order row');
    final symbol = _validInstrumentSymbol(row['symbol']);
    final id = _idString(row['orderId']);
    if (symbol == null || id == null) throw _invalidRows('Spot order identity');
    final instrument = _knownInstruments[ExchangeProduct.spot]?[symbol];
    final quoteCurrency = instrument?.quoteAsset.value;
    final nativePrice = ExchangeAmount.tryParse(row['price']);
    final price = quoteCurrency != null && nativePrice?.isPositive == true
        ? ExchangeValue<ExchangeMoney>.available(
            ExchangeMoney(amount: nativePrice!, currency: quoteCurrency),
          )
        : const ExchangeValue<ExchangeMoney>.unavailable(
            'Spot order price is unavailable or not positive.',
          );
    return ExchangeOrder(
      source: ExchangeSource.binance,
      product: ExchangeProduct.spot,
      kind: kind,
      symbol: symbol,
      nativeId: id,
      side: _optionalString(row['side'])?.toLowerCase() ?? '',
      status: _optionalString(row['status']) ?? 'unknown',
      quantity: _amountValue(row['origQty'], 'order quantity'),
      executedQuantity: _amountValue(row['executedQty'], 'executed quantity'),
      quoteAmount: _moneyValue(
        row['cummulativeQuoteQty'],
        quoteCurrency,
        'executed quote amount',
      ),
      createdAtMilliseconds: _intValue(row['time']),
      updatedAtMilliseconds: _intValue(row['updateTime']),
      price: price,
      countsTowardExecution: kind == ExchangeOrderKind.ordinary,
      nativeRecord: row,
    );
  }

  ExchangeOrder _futuresOrder(
    Object? value, {
    required ExchangeOrderKind kind,
    ExchangeProduct? fallbackProduct,
  }) {
    final row = _asStringKeyedMap(value);
    if (row == null) throw _invalidRows('Futures order row');
    final symbol = _validInstrumentSymbol(row['symbol']);
    final id = kind == ExchangeOrderKind.ordinary
        ? _idString(row['orderId'])
        : _idString(row['algoId']);
    if (symbol == null || id == null) {
      throw _invalidRows('Futures order identity');
    }
    final product =
        _knownFuturesInstrument(symbol)?.product ??
        _futuresProduct(_optionalString(row['contractType'])) ??
        fallbackProduct;
    final isConditional = kind == ExchangeOrderKind.conditional;
    final quoteCurrency = _knownFuturesInstrument(symbol)?.quoteAsset.value;
    final actualOrderId = _idString(row['actualOrderId']);
    return ExchangeOrder(
      source: ExchangeSource.binance,
      product: product,
      kind: kind,
      symbol: symbol,
      nativeId: id,
      side: _optionalString(row['side'])?.toLowerCase() ?? '',
      status:
          _optionalString(row[isConditional ? 'algoStatus' : 'status']) ??
          'unknown',
      quantity: isConditional
          ? _amountValue(
              row['quantity'] ?? row['origQty'],
              'conditional quantity',
            )
          : _amountValue(row['origQty'], 'order quantity'),
      executedQuantity: isConditional
          ? const ExchangeValue.unavailable(
              'Conditional parent does not establish an execution quantity.',
            )
          : _amountValue(row['executedQty'], 'executed quantity'),
      quoteAmount: isConditional
          ? const ExchangeValue.unavailable(
              'Conditional parent does not establish an execution value.',
            )
          : _moneyValue(
              row['cumQuote'],
              quoteCurrency,
              'executed quote amount',
            ),
      createdAtMilliseconds: _intValue(
        row[isConditional ? 'createTime' : 'time'],
      ),
      updatedAtMilliseconds: _intValue(row['updateTime']),
      price: _futuresOrderPrice(
        row,
        quoteCurrency,
        isConditional: isConditional,
      ),
      actualOrderId: actualOrderId,
      countsTowardExecution: !isConditional,
      nativeRecord: row,
    );
  }

  ExchangeInstrument? _knownFuturesInstrument(String symbol) =>
      _knownInstruments[ExchangeProduct.swap]?[symbol] ??
      _knownInstruments[ExchangeProduct.futures]?[symbol];

  ExchangeValue<ExchangeMoney> _futuresOrderPrice(
    Map<String, dynamic> row,
    String? quoteCurrency, {
    required bool isConditional,
  }) {
    final nativePrice = ExchangeAmount.tryParse(row['price']);
    if (quoteCurrency == null) {
      return const ExchangeValue.unavailable(
        'Futures order quote currency is unavailable.',
      );
    }
    if (nativePrice != null && nativePrice.isPositive) {
      return ExchangeValue.available(
        ExchangeMoney(amount: nativePrice, currency: quoteCurrency),
      );
    }
    if (!isConditional &&
        _optionalString(row['type'])?.toUpperCase() == 'MARKET') {
      final executed = ExchangeAmount.tryParse(row['executedQty']);
      final averagePrice = ExchangeAmount.tryParse(row['avgPrice']);
      if (executed != null &&
          executed.isPositive &&
          averagePrice != null &&
          averagePrice.isPositive) {
        return ExchangeValue.available(
          ExchangeMoney(amount: averagePrice, currency: quoteCurrency),
        );
      }
    }
    return const ExchangeValue.unavailable(
      'No positive native order or executed market price is available.',
    );
  }

  static ExchangeProduct? _futuresProduct(String? type) => switch (type) {
    'PERPETUAL' => ExchangeProduct.swap,
    'CURRENT_QUARTER' ||
    'NEXT_QUARTER' ||
    'CURRENT_QUARTER_DELIVERING' => ExchangeProduct.futures,
    _ => null,
  };

  static ExchangeReadException _invalidRows(String kind) =>
      ExchangeReadException(
        code: 'binance_invalid_response',
        message: 'Binance returned invalid $kind data.',
      );

  static ExchangeValue<ExchangeAmount> _amountValue(
    Object? value,
    String label,
  ) {
    final amount = ExchangeAmount.tryParse(value);
    return amount == null
        ? ExchangeValue<ExchangeAmount>.unavailable('$label is unavailable.')
        : ExchangeValue<ExchangeAmount>.available(amount);
  }

  static ExchangeValue<ExchangeMoney> _moneyValue(
    Object? amount,
    String? currency,
    String label,
  ) {
    final money = ExchangeMoney.tryParse(amount, currency);
    return money == null
        ? ExchangeValue<ExchangeMoney>.unavailable('$label is unavailable.')
        : ExchangeValue<ExchangeMoney>.available(money);
  }

  static ExchangeValue<String> _assetValue(Object? value) {
    final code = _assetCode(value);
    return code == null
        ? const ExchangeValue<String>.unavailable('Asset code is unavailable.')
        : ExchangeValue<String>.available(code);
  }

  static ExchangeValue<String> _stringValue(Object? value, String label) {
    final text = _optionalString(value);
    return text == null
        ? ExchangeValue<String>.unavailable('$label is unavailable.')
        : ExchangeValue<String>.available(text);
  }

  static String? _assetCode(Object? value) {
    if (value is! String) return null;
    final code = value.trim().toUpperCase();
    return RegExp(r'^[A-Z0-9]{1,20}$').hasMatch(code) ? code : null;
  }

  static String? _validInstrumentSymbol(Object? value) {
    if (value is! String) return null;
    final symbol = value.trim().toUpperCase();
    return RegExp(r'^[A-Z0-9]{1,40}$').hasMatch(symbol) ? symbol : null;
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String? _idString(Object? value) {
    if (value is String || value is num) {
      final id = value.toString().trim();
      return id.isEmpty ? null : id;
    }
    return null;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static Map<String, dynamic>? _asStringKeyedMap(Object? value) {
    if (value is! Map) return null;
    return value.map<String, dynamic>(
      (key, item) => MapEntry(key.toString(), item),
    );
  }

  static List<Object?>? _asList(Object? value) =>
      value is List ? value.cast<Object?>() : null;

  DateTime now() => _clock().toUtc();
}
