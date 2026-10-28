import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/okx_data_client.dart';
import '../network/okx_read_scope.dart';
import '../security/secure_storage_helper.dart';
import 'binance_exchange_reader.dart';
import 'binance_history_scan.dart';
import 'exchange_models.dart';
import 'exchange_quote_service.dart';
import 'exchange_readers.dart';
import 'okx_exchange_reader.dart';

/// Gives direct Binance reads the same secret-free, generation-aware lifetime
/// that OKX reads already receive from [okxCredentialReadScopeProvider].
class BinanceCredentialReadScope extends ChangeNotifier {
  BinanceCredentialReadScope(this._state) {
    _state.addListener(_notifyChanged);
  }

  final ValueListenable<BinanceCredentialSnapshot> _state;

  BinanceCredentialSnapshot get snapshot => _state.value;

  void _notifyChanged() => notifyListeners();

  @override
  void dispose() {
    _state.removeListener(_notifyChanged);
    super.dispose();
  }
}

final binanceCredentialReadScopeProvider =
    ChangeNotifierProvider<BinanceCredentialReadScope>((ref) {
      final storage = ref.watch(secureStorageProvider);
      return BinanceCredentialReadScope(storage.binanceCredentialState);
    });

final binanceCredentialSnapshotProvider = Provider<BinanceCredentialSnapshot>(
  (ref) => ref.watch(
    binanceCredentialReadScopeProvider.select((scope) => scope.snapshot),
  ),
);

@immutable
class ExchangeAccountResult {
  const ExchangeAccountResult({
    required this.source,
    required this.product,
    required this.account,
    this.error,
    this.isLoading = false,
    this.isTerminalFailure = false,
  });

  final ExchangeSource source;
  final ExchangeProduct? product;
  final ExchangeAccountSnapshot? account;
  final String? error;
  final bool isLoading;
  final bool isTerminalFailure;

  bool get isAvailable => account != null;
  bool get isComplete => account != null && account!.issues.isEmpty;
}

@immutable
class PortfolioBalanceRow {
  const PortfolioBalanceRow({
    required this.balance,
    required this.totalAmount,
    required this.valuation,
    this.quote,
  });

  final ExchangeBalance balance;
  final ExchangeValue<ExchangeAmount> totalAmount;
  final ExchangeValue<ExchangeMoney> valuation;
  final ExchangeQuote? quote;
}

@immutable
class CombinedExchangePortfolio {
  CombinedExchangePortfolio({
    required Iterable<ExchangeAccountResult> sources,
    required Iterable<PortfolioBalanceRow> rows,
    required this.totalEquity,
    required this.isPartial,
    required Iterable<String> warnings,
  }) : sources = List<ExchangeAccountResult>.unmodifiable(sources),
       rows = List<PortfolioBalanceRow>.unmodifiable(rows),
       warnings = List<String>.unmodifiable(warnings);

  final List<ExchangeAccountResult> sources;
  final List<PortfolioBalanceRow> rows;

  /// The app's existing USD/USDT reporting convention, without claiming an
  /// exchange-rate conversion between those two quote units.
  final ExchangeValue<ExchangeAmount> totalEquity;
  final bool isPartial;
  final List<String> warnings;

  bool get isLoading => sources.any((source) => source.isLoading);
}

@immutable
class ExchangePortfolioSourceData {
  ExchangePortfolioSourceData({
    required this.source,
    required this.product,
    required this.result,
    Iterable<PortfolioBalanceRow> rows = const <PortfolioBalanceRow>[],
    this.spotCatalog,
    this.credentialGeneration,
    required this.equityContribution,
    required this.valuationComplete,
    Iterable<String> warnings = const <String>[],
  }) : rows = List<PortfolioBalanceRow>.unmodifiable(rows),
       warnings = List<String>.unmodifiable(warnings);

  final ExchangeSource source;
  final ExchangeProduct? product;
  final ExchangeAccountResult result;
  final List<PortfolioBalanceRow> rows;
  final ExchangeCatalog? spotCatalog;
  final int? credentialGeneration;
  final ExchangeValue<ExchangeAmount> equityContribution;
  final bool valuationComplete;
  final List<String> warnings;
}

Future<ExchangeAccountResult> _readOkxAccount(
  Ref ref,
  OkxExchangeReader reader,
) async {
  try {
    final account = await runOkxPrivateRead<ExchangeAccountSnapshot>(
      ref: ref,
      requestKey: 'portfolio/combined/account',
      load: (cancelToken) => reader.getAccountBalance(cancelToken: cancelToken),
    );
    return ExchangeAccountResult(
      source: ExchangeSource.okx,
      product: null,
      account: account,
    );
  } catch (error) {
    return ExchangeAccountResult(
      source: ExchangeSource.okx,
      product: null,
      account: null,
      error: _safeReadError(error),
      isTerminalFailure: _isTerminalReadFailure(error),
    );
  }
}

Future<_CatalogReadResult> _readBinanceSpotCatalog(
  BinanceExchangeReader reader,
  BinanceCredentialSnapshot generation,
  CancelToken cancelToken,
) async {
  try {
    final catalog = await reader.getSpotCatalog(
      cancelToken: cancelToken,
      expectedGeneration: generation,
      reuseForPortfolio: true,
    );
    return _CatalogReadResult(catalog: catalog);
  } catch (error) {
    return _CatalogReadResult(
      error: _safeReadError(error),
      isTerminalFailure: _isTerminalReadFailure(error),
    );
  }
}

Future<ExchangeAccountResult> _readBinanceSpotAccount(
  BinanceExchangeReader reader,
  BinanceCredentialSnapshot generation,
  CancelToken cancelToken,
) async {
  try {
    final account = await reader.getSpotAccount(
      cancelToken: cancelToken,
      expectedGeneration: generation,
    );
    return ExchangeAccountResult(
      source: ExchangeSource.binance,
      product: ExchangeProduct.spot,
      account: account,
    );
  } catch (error) {
    return ExchangeAccountResult(
      source: ExchangeSource.binance,
      product: ExchangeProduct.spot,
      account: null,
      error: _safeReadError(error),
      isTerminalFailure: _isTerminalReadFailure(error),
    );
  }
}

Future<ExchangeAccountResult> _readBinanceFuturesAccount(
  BinanceExchangeReader reader,
  BinanceCredentialSnapshot generation,
  CancelToken cancelToken,
) async {
  try {
    final account = await reader.getFuturesAccount(
      cancelToken: cancelToken,
      expectedGeneration: generation,
    );
    return ExchangeAccountResult(
      source: ExchangeSource.binance,
      product: ExchangeProduct.swap,
      account: account,
    );
  } catch (error) {
    return ExchangeAccountResult(
      source: ExchangeSource.binance,
      product: ExchangeProduct.swap,
      account: null,
      error: _safeReadError(error),
      isTerminalFailure: _isTerminalReadFailure(error),
    );
  }
}

class _CatalogReadResult {
  const _CatalogReadResult({
    this.catalog,
    this.error,
    this.isTerminalFailure = false,
  });

  final ExchangeCatalog? catalog;
  final String? error;
  final bool isTerminalFailure;
}

List<ExchangeInstrument> _portfolioQuoteInstruments({
  required Iterable<ExchangeAccountResult> accounts,
  required ExchangeCatalog? spotCatalog,
}) {
  final binanceSpotByAsset = <String, ExchangeInstrument>{};
  for (final instrument
      in spotCatalog?.instruments ?? const <ExchangeInstrument>[]) {
    if (instrument.product != ExchangeProduct.spot ||
        instrument.quoteAsset.value?.toUpperCase() != 'USDT') {
      continue;
    }
    final base = instrument.baseAsset.value?.toUpperCase();
    if (base != null) binanceSpotByAsset.putIfAbsent(base, () => instrument);
  }

  final output = <String, ExchangeInstrument>{};
  for (final result in accounts) {
    final account = result.account;
    if (account == null) continue;
    for (final balance in account.balances) {
      final total = _balanceTotal(balance);
      if (!total.isAvailable ||
          total.value!.isZero ||
          _hasSupportedNativeValuation(balance)) {
        continue;
      }
      final asset = balance.asset.toUpperCase();
      if (_isReportingCurrency(asset)) continue;
      ExchangeInstrument? instrument;
      if (balance.source == ExchangeSource.binance) {
        instrument = binanceSpotByAsset[asset];
      } else {
        instrument = ExchangeInstrument(
          source: ExchangeSource.okx,
          product: ExchangeProduct.spot,
          symbol: '$asset-USDT',
          baseAsset: ExchangeValue<String>.available(asset),
          quoteAsset: const ExchangeValue<String>.available('USDT'),
          settlementAsset: const ExchangeValue<String>.unavailable(
            'Spot instruments do not have a settlement asset.',
          ),
        );
      }
      if (instrument != null) {
        final key = ExchangeQuoteKey(
          source: instrument.source,
          product: instrument.product,
          instrument: instrument.symbol,
        );
        output.putIfAbsent(key.value, () => instrument!);
      }
    }
  }
  return output.values.toList(growable: false);
}

bool _hasSupportedNativeValuation(ExchangeBalance balance) {
  final value = balance.reportedUsdValue?.value;
  return value != null && _isReportingCurrency(value.currency);
}

bool _isReportingCurrency(String currency) =>
    currency.toUpperCase() == 'USD' || currency.toUpperCase() == 'USDT';

ExchangeValue<ExchangeMoney> _balanceValuation({
  required ExchangeBalance balance,
  required ExchangeValue<ExchangeAmount> totalAmount,
  required ExchangeQuoteSnapshot? quotes,
  required ExchangeCatalog? spotCatalog,
  Duration quoteFreshness = const Duration(seconds: 15),
}) {
  final nativeValue = balance.reportedUsdValue;
  if (nativeValue?.value != null &&
      _isReportingCurrency(nativeValue!.value!.currency)) {
    return ExchangeValue<ExchangeMoney>.available(nativeValue.value!);
  }
  final amount = totalAmount.value;
  if (amount == null) {
    return const ExchangeValue<ExchangeMoney>.unavailable(
      'The balance amount is unavailable.',
    );
  }
  if (_isReportingCurrency(balance.asset)) {
    return ExchangeValue<ExchangeMoney>.available(
      ExchangeMoney(amount: amount, currency: balance.asset.toUpperCase()),
    );
  }
  if (amount.isZero) {
    return ExchangeValue<ExchangeMoney>.available(
      ExchangeMoney(amount: ExchangeAmount.tryParse('0')!, currency: 'USDT'),
    );
  }
  final key = _quoteKeyFor(balance, spotCatalog);
  final quote = key == null
      ? null
      : _freshQuote(quotes?.values[key]?.value, quoteFreshness);
  if (quote == null) {
    return const ExchangeValue<ExchangeMoney>.unavailable(
      'A same-exchange Spot quote is unavailable.',
    );
  }
  return ExchangeValue<ExchangeMoney>.available(
    ExchangeMoney(
      amount: ExchangeAmount.multiply(amount, quote.price),
      currency: quote.quoteCurrency,
    ),
  );
}

ExchangeQuoteKey? _quoteKeyFor(
  ExchangeBalance balance,
  ExchangeCatalog? spotCatalog,
) {
  final source = balance.source;
  final product = balance.product ?? ExchangeProduct.spot;
  if (source == ExchangeSource.binance && product != ExchangeProduct.spot) {
    return null;
  }
  final asset = balance.asset.toUpperCase();
  if (_isReportingCurrency(asset)) return null;
  String? symbol;
  if (source == ExchangeSource.okx) {
    symbol = '$asset-USDT';
  } else {
    final instrument = _firstOrNull(
      (spotCatalog?.instruments ?? const <ExchangeInstrument>[]).where(
        (candidate) =>
            candidate.product == ExchangeProduct.spot &&
            candidate.baseAsset.value?.toUpperCase() == asset &&
            candidate.quoteAsset.value?.toUpperCase() == 'USDT',
      ),
    );
    symbol = instrument?.symbol;
  }
  if (symbol == null) return null;
  return ExchangeQuoteKey(
    source: source,
    product: ExchangeProduct.spot,
    instrument: symbol,
  );
}

String _sourceLabel(ExchangeSource source, ExchangeProduct? product) {
  if (source == ExchangeSource.okx) return 'OKX Unified';
  return switch (product) {
    ExchangeProduct.spot => 'Binance Spot',
    ExchangeProduct.swap || ExchangeProduct.futures => 'Binance Futures',
    ExchangeProduct.margin => 'Binance Margin',
    null => 'Binance',
  };
}

String _safeReadError(Object error) {
  if (error is ExchangeReadException) {
    switch (error.code) {
      case 'binance_network_error':
        return kIsWeb
            ? 'Cannot reach Binance from this browser. Check your connection; browser or network restrictions may also block requests.'
            : 'Cannot reach Binance. Check your connection and retry.';
      case 'binance_timeout':
        return 'Binance did not respond in time. Retry in a moment.';
      case 'binance_rate_limited':
        return 'Binance rate limit reached. Retry shortly.';
      case 'binance_ip_banned':
        return 'Binance temporarily blocked reads from this network. Retry later.';
      case 'binance_host_paused':
      case 'binance_budget_metadata_unavailable':
        final retryAt = error.retryAt;
        if (retryAt != null && retryAt.isAfter(DateTime.now())) {
          final localRetryAt = retryAt.toLocal();
          final hour = localRetryAt.hour.toString().padLeft(2, '0');
          final minute = localRetryAt.minute.toString().padLeft(2, '0');
          return 'Binance reads are paused. Retry after $hour:$minute.';
        }
        return 'Binance reads are paused. Retry later.';
      case 'binance_authentication_failed':
        return 'Binance rejected the API key. Check the key, secret and permissions.';
      case 'binance_timestamp_invalid':
        return 'Binance rejected the request time. Check your device clock and retry.';
      case 'binance_http_error':
      case 'binance_api_error':
      case 'binance_invalid_response':
        return 'Binance could not complete the request. Retry later.';
      case 'binance_credentials_required':
      case 'binance_credentials_unavailable':
      case 'request_cancelled':
      case 'credentials_changed':
        return error.message;
      default:
        return 'The exchange account data is unavailable. Retry the account read.';
    }
  }
  if (error is OkxDataException) return error.message;
  if (error is BinanceCredentialStorageException) {
    return 'Binance credentials could not be loaded. Save the key and secret again.';
  }
  if (error is DioException) {
    return 'The exchange request could not be completed. Check the connection and retry.';
  }
  return 'The exchange account data is unavailable. Retry the account read.';
}

final okxPortfolioSourceProvider =
    FutureProvider.autoDispose<ExchangePortfolioSourceData>((ref) async {
      final generation = ref.watch(okxCredentialSnapshotProvider);
      final reader = ref.watch(okxExchangeReaderProvider);
      final result = await _readOkxAccount(ref, reader);
      if (result.account == null) {
        return _unavailablePortfolioSource(
          result,
          credentialGeneration: generation.generation,
        );
      }
      final accounts = <ExchangeAccountResult>[result];
      final rows = _portfolioRows(
        accounts: accounts,
        spotCatalog: null,
        quotes: null,
      );
      final equity = _reportedEquityContribution(result.account!);
      final valuationComplete =
          equity.value != null && result.account!.issues.isEmpty;
      return ExchangePortfolioSourceData(
        source: ExchangeSource.okx,
        product: null,
        result: result,
        rows: rows,
        spotCatalog: null,
        credentialGeneration: generation.generation,
        equityContribution: equity,
        valuationComplete: valuationComplete,
        warnings: <String>[
          if (result.account!.issues.isNotEmpty)
            'OKX returned incomplete account data.',
          if (equity.value == null)
            'OKX reported equity is unavailable in USD/USDT reporting units.',
        ],
      );
    });

final binanceSpotPortfolioSourceProvider =
    FutureProvider.autoDispose<ExchangePortfolioSourceData>((ref) async {
      final generation = ref.watch(binanceCredentialSnapshotProvider);
      final reader = ref.watch(binanceExchangeReaderProvider);
      final catalogToken = CancelToken();
      final accountToken = CancelToken();
      ref.onDispose(() {
        if (!catalogToken.isCancelled) {
          catalogToken.cancel('Binance Spot portfolio disposed.');
        }
        if (!accountToken.isCancelled) {
          accountToken.cancel('Binance Spot portfolio disposed.');
        }
      });
      final catalog = await _readBinanceSpotCatalog(
        reader,
        generation,
        catalogToken,
      );
      final result = await _readBinanceSpotAccount(
        reader,
        generation,
        accountToken,
      );
      if (reader.credentialState.value != generation) {
        return _loadingPortfolioSource(
          ExchangeSource.binance,
          ExchangeProduct.spot,
        );
      }
      final sourceResult = ExchangeAccountResult(
        source: result.source,
        product: result.product,
        account: result.account,
        error: result.error,
        isLoading: result.isLoading,
        isTerminalFailure:
            result.isTerminalFailure || catalog.isTerminalFailure,
      );
      if (result.account == null) {
        return _unavailablePortfolioSource(
          sourceResult,
          credentialGeneration: generation.generation,
          warnings: <String>[
            if (catalog.error != null)
              'Binance Spot catalog data is unavailable.',
          ],
        );
      }
      final rows = _portfolioRows(
        accounts: <ExchangeAccountResult>[sourceResult],
        spotCatalog: catalog.catalog,
        quotes: null,
      );
      return ExchangePortfolioSourceData(
        source: ExchangeSource.binance,
        product: ExchangeProduct.spot,
        result: sourceResult,
        rows: rows,
        spotCatalog: catalog.catalog,
        credentialGeneration: generation.generation,
        equityContribution: const ExchangeValue<ExchangeAmount>.unavailable(
          'Binance Spot valuation quotes are loading.',
        ),
        valuationComplete: false,
        warnings: <String>[
          if (catalog.error != null)
            'Binance Spot catalog data is unavailable.',
          if (catalog.catalog?.issues.isNotEmpty == true)
            'Binance Spot catalog coverage is incomplete.',
          if (result.account!.issues.isNotEmpty)
            'Binance Spot returned incomplete account data.',
        ],
      );
    });

final binanceFuturesPortfolioSourceProvider =
    FutureProvider.autoDispose<ExchangePortfolioSourceData>((ref) async {
      final generation = ref.watch(binanceCredentialSnapshotProvider);
      final reader = ref.watch(binanceExchangeReaderProvider);
      final token = CancelToken();
      ref.onDispose(() {
        if (!token.isCancelled) {
          token.cancel('Binance Futures portfolio disposed.');
        }
      });
      final result = await _readBinanceFuturesAccount(
        reader,
        generation,
        token,
      );
      if (reader.credentialState.value != generation) {
        return _loadingPortfolioSource(
          ExchangeSource.binance,
          ExchangeProduct.swap,
        );
      }
      if (result.account == null) {
        return _unavailablePortfolioSource(
          result,
          credentialGeneration: generation.generation,
        );
      }
      final rows = _portfolioRows(
        accounts: <ExchangeAccountResult>[result],
        spotCatalog: null,
        quotes: null,
      );
      final equity = _reportedEquityContribution(result.account!);
      return ExchangePortfolioSourceData(
        source: ExchangeSource.binance,
        product: ExchangeProduct.swap,
        result: result,
        rows: rows,
        spotCatalog: null,
        credentialGeneration: generation.generation,
        equityContribution: equity,
        valuationComplete:
            equity.value != null && result.account!.issues.isEmpty,
        warnings: <String>[
          if (result.account!.issues.isNotEmpty)
            'Binance Futures returned incomplete account data.',
          if (equity.value == null)
            'Binance Futures margin equity or denomination is unavailable.',
        ],
      );
    });

final okxPortfolioValuationProvider =
    FutureProvider.autoDispose<ExchangePortfolioSourceData>((ref) async {
      final generation = ref.watch(okxCredentialSnapshotProvider);
      final sourceAsync = ref.watch(okxPortfolioSourceProvider);
      final source = sourceAsync.valueOrNull;
      if (source == null || generation.rotating) {
        return _loadingPortfolioSource(ExchangeSource.okx, null);
      }
      return _valuePortfolioSource(
        ref,
        ref.watch(exchangeQuoteServiceProvider),
        sourceAsync.isLoading ? _markPortfolioSourceRefreshing(source) : source,
        currentGeneration: () =>
            ref.read(okxCredentialSnapshotProvider).generation,
        expectedGeneration: generation.generation,
      );
    });

final binanceSpotPortfolioValuationProvider =
    FutureProvider.autoDispose<ExchangePortfolioSourceData>((ref) async {
      final generation = ref.watch(binanceCredentialSnapshotProvider);
      final reader = ref.watch(binanceExchangeReaderProvider);
      final sourceAsync = ref.watch(binanceSpotPortfolioSourceProvider);
      final source = sourceAsync.valueOrNull;
      if (source == null || generation.rotating) {
        return _loadingPortfolioSource(
          ExchangeSource.binance,
          ExchangeProduct.spot,
        );
      }
      return _valuePortfolioSource(
        ref,
        ref.watch(exchangeQuoteServiceProvider),
        sourceAsync.isLoading ? _markPortfolioSourceRefreshing(source) : source,
        currentGeneration: () => reader.credentialState.value.generation,
        expectedGeneration: generation.generation,
      );
    });

final binanceFuturesPortfolioValuationProvider =
    FutureProvider.autoDispose<ExchangePortfolioSourceData>((ref) async {
      final generation = ref.watch(binanceCredentialSnapshotProvider);
      final reader = ref.watch(binanceExchangeReaderProvider);
      final sourceAsync = ref.watch(binanceFuturesPortfolioSourceProvider);
      final source = sourceAsync.valueOrNull;
      if (source == null || generation.rotating) {
        return _loadingPortfolioSource(
          ExchangeSource.binance,
          ExchangeProduct.swap,
        );
      }
      return _valuePortfolioSource(
        ref,
        ref.watch(exchangeQuoteServiceProvider),
        sourceAsync.isLoading ? _markPortfolioSourceRefreshing(source) : source,
        currentGeneration: () => reader.credentialState.value.generation,
        expectedGeneration: generation.generation,
      );
    });

Future<ExchangePortfolioSourceData> _valuePortfolioSource(
  Ref ref,
  ExchangeQuoteService quoteService,
  ExchangePortfolioSourceData source, {
  required int expectedGeneration,
  required int Function() currentGeneration,
}) async {
  if (source.credentialGeneration != expectedGeneration) {
    return _loadingPortfolioSource(source.source, source.product);
  }
  if (source.result.account == null) return source;
  final accounts = <ExchangeAccountResult>[source.result];
  final quoteRead = await _loadPortfolioQuotes(
    ref,
    quoteService,
    accounts: accounts,
    spotCatalog: source.spotCatalog,
  );
  if (currentGeneration() != expectedGeneration) {
    return _loadingPortfolioSource(source.source, source.product);
  }
  final rows = _portfolioRows(
    accounts: accounts,
    spotCatalog: source.spotCatalog,
    quotes: quoteRead.snapshot,
    quoteFreshness: quoteService.freshness,
  );
  final equity = source.product == ExchangeProduct.spot
      ? _spotEquityContribution(rows)
      : _reportedEquityContribution(source.result.account!);
  final valuationComplete =
      equity.value != null &&
      source.result.account!.issues.isEmpty &&
      source.spotCatalog?.catalogComplete != false &&
      rows.every(_rowHasRequiredValuation);
  return ExchangePortfolioSourceData(
    source: source.source,
    product: source.product,
    result: source.result,
    rows: rows,
    spotCatalog: source.spotCatalog,
    credentialGeneration: source.credentialGeneration,
    equityContribution: equity,
    valuationComplete: valuationComplete,
    warnings: <String>[
      ...source.warnings,
      if (quoteRead.error != null) quoteRead.error!,
      if (source.result.account!.issues.isNotEmpty)
        '${_sourceLabel(source.source, source.product)} returned incomplete account data.',
      if (equity.value == null && source.product == ExchangeProduct.spot)
        'Binance Spot equity is incomplete because one or more assets lack a fresh same-exchange quote.',
      if (equity.value == null && source.product != ExchangeProduct.spot)
        '${_sourceLabel(source.source, source.product)} reported equity is unavailable in USD/USDT units.',
      if (rows.any((row) => !_rowHasRequiredValuation(row)))
        'Some ${_sourceLabel(source.source, source.product)} assets do not have a fresh same-exchange Spot valuation.',
    ],
  );
}

final combinedExchangePortfolioProvider = Provider.autoDispose((ref) {
  final okxGeneration = ref.watch(okxCredentialSnapshotProvider);
  final binanceGeneration = ref.watch(binanceCredentialSnapshotProvider);
  final okx = _portfolioSourceFromAsync(
    ref.watch(okxPortfolioValuationProvider),
    ExchangeSource.okx,
    null,
    expectedGeneration: okxGeneration.generation,
    isRotating: okxGeneration.rotating,
  );
  final binanceSpot = _portfolioSourceFromAsync(
    ref.watch(binanceSpotPortfolioValuationProvider),
    ExchangeSource.binance,
    ExchangeProduct.spot,
    expectedGeneration: binanceGeneration.generation,
    isRotating: binanceGeneration.rotating,
  );
  final binanceFutures = _portfolioSourceFromAsync(
    ref.watch(binanceFuturesPortfolioValuationProvider),
    ExchangeSource.binance,
    ExchangeProduct.swap,
    expectedGeneration: binanceGeneration.generation,
    isRotating: binanceGeneration.rotating,
  );
  final sourceData = <ExchangePortfolioSourceData>[
    okx,
    binanceSpot,
    binanceFutures,
  ];
  var total = ExchangeAmount.tryParse('0')!;
  var hasTotal = false;
  var isPartial = false;
  final warnings = <String>[];
  for (final source in sourceData) {
    warnings.addAll(source.warnings);
    final result = source.result;
    if (result.isLoading || !result.isAvailable || !source.valuationComplete) {
      isPartial = true;
    }
    final contribution = source.equityContribution.value;
    if (contribution != null) {
      total = ExchangeAmount.add(total, contribution);
      hasTotal = true;
    }
  }
  final rows = sourceData.expand((source) => source.rows).toList()
    ..sort(_comparePortfolioRows);
  final hasIssues = sourceData.any(
    (source) => source.result.account?.issues.isNotEmpty == true,
  );
  return CombinedExchangePortfolio(
    sources: sourceData.map((source) => source.result),
    rows: rows,
    totalEquity: hasTotal
        ? ExchangeValue<ExchangeAmount>.available(total)
        : const ExchangeValue<ExchangeAmount>.unavailable(
            'No account equity value is currently available.',
          ),
    isPartial: isPartial || hasIssues,
    warnings: warnings.toSet().toList(growable: false),
  );
});

ExchangePortfolioSourceData _portfolioSourceFromAsync(
  AsyncValue<ExchangePortfolioSourceData> value,
  ExchangeSource source,
  ExchangeProduct? product, {
  required int expectedGeneration,
  required bool isRotating,
}) {
  if (value.isLoading) {
    final previous = value.valueOrNull;
    if (!isRotating &&
        previous != null &&
        previous.credentialGeneration == expectedGeneration) {
      return _markPortfolioSourceRefreshing(
        _expireStalePortfolioQuotes(previous),
      );
    }
    return _loadingPortfolioSource(source, product);
  }
  if (value.hasError) {
    final error = _safeReadError(value.error as Object);
    return _unavailablePortfolioSource(
      ExchangeAccountResult(
        source: source,
        product: product,
        account: null,
        error: error,
        isTerminalFailure: _isTerminalReadFailure(value.error!),
      ),
      credentialGeneration: expectedGeneration,
    );
  }
  return value.requireValue;
}

ExchangePortfolioSourceData _loadingPortfolioSource(
  ExchangeSource source,
  ExchangeProduct? product,
) => ExchangePortfolioSourceData(
  source: source,
  product: product,
  result: ExchangeAccountResult(
    source: source,
    product: product,
    account: null,
    isLoading: true,
  ),
  equityContribution: const ExchangeValue<ExchangeAmount>.unavailable(
    'Account data is loading.',
  ),
  valuationComplete: false,
  warnings: <String>['${_sourceLabel(source, product)} is loading.'],
);

ExchangePortfolioSourceData _markPortfolioSourceRefreshing(
  ExchangePortfolioSourceData source,
) {
  if (source.result.isLoading) return source;
  return ExchangePortfolioSourceData(
    source: source.source,
    product: source.product,
    result: ExchangeAccountResult(
      source: source.result.source,
      product: source.result.product,
      account: source.result.account,
      error: source.result.error,
      isLoading: true,
      isTerminalFailure: source.result.isTerminalFailure,
    ),
    rows: source.rows,
    spotCatalog: source.spotCatalog,
    credentialGeneration: source.credentialGeneration,
    equityContribution: source.equityContribution,
    valuationComplete: source.valuationComplete,
    warnings: <String>[
      ...source.warnings,
      '${_sourceLabel(source.source, source.product)} account is refreshing; retained balances may be stale.',
    ],
  );
}

ExchangePortfolioSourceData _unavailablePortfolioSource(
  ExchangeAccountResult result, {
  Iterable<String> warnings = const <String>[],
  int? credentialGeneration,
}) => ExchangePortfolioSourceData(
  source: result.source,
  product: result.product,
  result: result,
  credentialGeneration: credentialGeneration,
  equityContribution: const ExchangeValue<ExchangeAmount>.unavailable(
    'Account equity is unavailable.',
  ),
  valuationComplete: false,
  warnings: <String>[
    if (result.error != null)
      '${_sourceLabel(result.source, result.product)}: ${result.error}',
    ...warnings,
  ],
);

Future<_QuoteReadResult> _loadPortfolioQuotes(
  Ref ref,
  ExchangeQuoteService service, {
  required Iterable<ExchangeAccountResult> accounts,
  required ExchangeCatalog? spotCatalog,
}) async {
  final instruments = _portfolioQuoteInstruments(
    accounts: accounts,
    spotCatalog: spotCatalog,
  );
  if (instruments.isEmpty) return const _QuoteReadResult();
  final owner = service.createOwner();
  ref.onDispose(owner.dispose);
  try {
    return _QuoteReadResult(
      snapshot: await service.loadQuotes(
        owner: owner,
        instruments: instruments,
      ),
    );
  } catch (_) {
    return const _QuoteReadResult(
      error: 'Some same-exchange Spot valuation quotes are unavailable.',
    );
  }
}

class _QuoteReadResult {
  const _QuoteReadResult({this.snapshot, this.error});

  final ExchangeQuoteSnapshot? snapshot;
  final String? error;
}

List<PortfolioBalanceRow> _portfolioRows({
  required Iterable<ExchangeAccountResult> accounts,
  required ExchangeCatalog? spotCatalog,
  required ExchangeQuoteSnapshot? quotes,
  Duration quoteFreshness = const Duration(seconds: 15),
}) => accounts
    .where((source) => source.account != null)
    .expand((source) => source.account!.balances)
    .where((balance) {
      if (balance.source != ExchangeSource.binance) return true;
      final total = _balanceTotal(balance);
      return !total.isAvailable || !total.value!.isZero;
    })
    .map((balance) {
      final amount = _balanceTotal(balance);
      final valuation = _balanceValuation(
        balance: balance,
        totalAmount: amount,
        quotes: quotes,
        spotCatalog: spotCatalog,
        quoteFreshness: quoteFreshness,
      );
      final key = _quoteKeyFor(balance, spotCatalog);
      return PortfolioBalanceRow(
        balance: balance,
        totalAmount: amount,
        valuation: valuation,
        quote: key == null
            ? null
            : _freshQuote(quotes?.values[key]?.value, quoteFreshness),
      );
    })
    .toList(growable: false);

ExchangeValue<ExchangeAmount> _balanceTotal(ExchangeBalance balance) {
  final available = balance.availableTotal;
  if (available.value != null) return available;
  final reported = balance.reportedTotal;
  if ((balance.product == ExchangeProduct.swap ||
          balance.product == ExchangeProduct.futures) &&
      reported?.value != null) {
    return reported!;
  }
  return available;
}

ExchangeValue<ExchangeAmount> _reportedEquityContribution(
  ExchangeAccountSnapshot account,
) {
  final equity = account.reportedEquity.value;
  if (equity == null || !_isReportingCurrency(equity.currency)) {
    return const ExchangeValue<ExchangeAmount>.unavailable(
      'Reported equity is unavailable in USD/USDT reporting units.',
    );
  }
  return ExchangeValue<ExchangeAmount>.available(equity.amount);
}

ExchangeValue<ExchangeAmount> _spotEquityContribution(
  Iterable<PortfolioBalanceRow> rows,
) {
  var amount = ExchangeAmount.tryParse('0')!;
  for (final row in rows) {
    if (row.totalAmount.value == null) {
      return const ExchangeValue<ExchangeAmount>.unavailable(
        'A Spot asset balance is unavailable.',
      );
    }
    final value = row.valuation.value;
    if (value == null || !_isReportingCurrency(value.currency)) {
      if (!row.totalAmount.value!.isZero) {
        return const ExchangeValue<ExchangeAmount>.unavailable(
          'A Spot asset valuation is unavailable.',
        );
      }
      continue;
    }
    amount = ExchangeAmount.add(amount, value.amount);
  }
  return ExchangeValue<ExchangeAmount>.available(amount);
}

bool _rowHasRequiredValuation(PortfolioBalanceRow row) {
  if (row.totalAmount.value == null || row.totalAmount.value!.isZero) {
    return row.totalAmount.value != null;
  }
  if (row.balance.product == ExchangeProduct.swap ||
      row.balance.product == ExchangeProduct.futures) {
    return true;
  }
  final value = row.valuation.value;
  return value != null && _isReportingCurrency(value.currency);
}

ExchangeQuote? _freshQuote(ExchangeQuote? quote, Duration freshness) {
  if (quote == null) return null;
  final age = DateTime.now().toUtc().difference(quote.observedAt.toUtc());
  return !age.isNegative && age < freshness ? quote : null;
}

ExchangePortfolioSourceData _expireStalePortfolioQuotes(
  ExchangePortfolioSourceData source,
) {
  const freshness = Duration(seconds: 15);
  final rows = source.rows
      .map((row) {
        if (row.quote == null || _freshQuote(row.quote, freshness) != null) {
          return row;
        }
        return PortfolioBalanceRow(
          balance: row.balance,
          totalAmount: row.totalAmount,
          valuation: const ExchangeValue<ExchangeMoney>.unavailable(
            'The same-exchange Spot quote has expired.',
          ),
          quote: null,
        );
      })
      .toList(growable: false);
  final equity = source.product == ExchangeProduct.spot
      ? _spotEquityContribution(rows)
      : source.equityContribution;
  final complete =
      source.valuationComplete &&
      equity.value != null &&
      rows.every(_rowHasRequiredValuation);
  return ExchangePortfolioSourceData(
    source: source.source,
    product: source.product,
    result: source.result,
    rows: rows,
    spotCatalog: source.spotCatalog,
    credentialGeneration: source.credentialGeneration,
    equityContribution: equity,
    valuationComplete: complete,
    warnings: <String>[
      ...source.warnings,
      if (rows.any(
        (row) =>
            row.quote == null &&
            row.totalAmount.value != null &&
            !row.totalAmount.value!.isZero &&
            !_isReportingCurrency(row.balance.asset) &&
            row.balance.product != ExchangeProduct.swap &&
            row.balance.product != ExchangeProduct.futures,
      ))
        'Some same-exchange Spot valuation quotes have expired.',
      if (source.product == ExchangeProduct.spot && equity.value == null)
        'Binance Spot equity is incomplete because fresh quotes are unavailable.',
    ],
  );
}

int _comparePortfolioRows(PortfolioBalanceRow left, PortfolioBalanceRow right) {
  final bySource = left.balance.source.name.compareTo(
    right.balance.source.name,
  );
  if (bySource != 0) return bySource;
  final byProduct = (left.balance.product?.name ?? 'unified').compareTo(
    right.balance.product?.name ?? 'unified',
  );
  if (byProduct != 0) return byProduct;
  final byWallet = left.balance.wallet.compareTo(right.balance.wallet);
  return byWallet != 0
      ? byWallet
      : left.balance.asset.compareTo(right.balance.asset);
}

bool _isTerminalReadFailure(Object error) {
  if (error is BinanceCredentialStorageException) return true;
  if (error is OkxDataException) {
    return const {
      'okx_credentials_required',
      'okx_credentials_rotating',
      'okx_authentication_failed',
      'okx_timestamp_invalid',
    }.contains(error.code);
  }
  if (error is ExchangeReadException) {
    return const {
      'binance_credentials_required',
      'binance_credentials_unavailable',
      'binance_authentication_failed',
      'binance_credential_generation_changed',
    }.contains(error.code);
  }
  if (error is DioException) {
    return error.response?.statusCode == 401 ||
        error.response?.statusCode == 403;
  }
  return false;
}

void invalidateCombinedPortfolioSources(WidgetRef ref, {bool force = false}) {
  final okx = ref.read(okxPortfolioSourceProvider);
  final spot = ref.read(binanceSpotPortfolioSourceProvider);
  final futures = ref.read(binanceFuturesPortfolioSourceProvider);
  bool shouldRefreshSource(AsyncValue<ExchangePortfolioSourceData> current) {
    if (current.isLoading) return false;
    if (force) return true;
    final previous = current.valueOrNull;
    return !current.isLoading && previous?.result.isTerminalFailure != true;
  }

  bool shouldRefreshQuotes(AsyncValue<ExchangePortfolioSourceData> current) {
    if (force) return true;
    return current.valueOrNull?.result.isTerminalFailure != true;
  }

  if (shouldRefreshSource(okx)) {
    ref.invalidate(okxPortfolioSourceProvider);
  }
  if (shouldRefreshSource(spot)) {
    ref.invalidate(binanceSpotPortfolioSourceProvider);
  }
  if (shouldRefreshSource(futures)) {
    ref.invalidate(binanceFuturesPortfolioSourceProvider);
  }
  if (shouldRefreshQuotes(okx)) ref.invalidate(okxPortfolioValuationProvider);
  if (shouldRefreshQuotes(spot)) {
    ref.invalidate(binanceSpotPortfolioValuationProvider);
  }
  if (shouldRefreshQuotes(futures)) {
    ref.invalidate(binanceFuturesPortfolioValuationProvider);
  }
}

@immutable
class ExchangeRowsResult<T> {
  const ExchangeRowsResult({
    required this.source,
    required this.product,
    required this.rows,
    required this.isApplicable,
    required this.isComplete,
    this.error,
    this.isTerminalFailure = false,
    this.isLoading = false,
    this.generation,
  });

  const ExchangeRowsResult.notApplicable({
    required this.source,
    required this.product,
  }) : rows = const [],
       isApplicable = false,
       isComplete = true,
       error = null,
       isTerminalFailure = false,
       isLoading = false,
       generation = null;

  const ExchangeRowsResult.success({
    required this.source,
    required this.product,
    required this.rows,
    this.isComplete = true,
    this.error,
    this.isLoading = false,
    this.generation,
  }) : isApplicable = true,
       isTerminalFailure = false;

  const ExchangeRowsResult.failure({
    required this.source,
    required this.product,
    required this.error,
    this.isTerminalFailure = false,
    this.generation,
  }) : rows = const [],
       isApplicable = true,
       isComplete = false,
       isLoading = false;

  const ExchangeRowsResult.loading({
    required this.source,
    required this.product,
    required this.generation,
  }) : rows = const [],
       isApplicable = true,
       isComplete = false,
       error = null,
       isTerminalFailure = false,
       isLoading = true;

  final ExchangeSource source;
  final ExchangeProduct? product;
  final List<T> rows;
  final bool isApplicable;
  final bool isComplete;
  final String? error;
  final bool isTerminalFailure;
  final bool isLoading;
  final int? generation;
}

@immutable
class CombinedExchangeRows<T> {
  CombinedExchangeRows({required Iterable<ExchangeRowsResult<T>> sources})
    : sources = List<ExchangeRowsResult<T>>.unmodifiable(sources),
      rows = List<T>.unmodifiable(sources.expand((result) => result.rows));

  final List<ExchangeRowsResult<T>> sources;
  final List<T> rows;

  bool get isPartial => sources.any(
    (source) => source.isApplicable && (!source.isComplete || source.isLoading),
  );

  bool get isLoading => sources.any((source) => source.isLoading);

  bool get hasAvailableSource => sources.any(
    (source) =>
        source.isApplicable && (source.isComplete || source.rows.isNotEmpty),
  );
}

enum CombinedOrderReadType { positions, pending, history }

@immutable
class CombinedOrderReadRequest {
  const CombinedOrderReadRequest({required this.type, required this.filter});

  final CombinedOrderReadType type;
  final String filter;

  @override
  bool operator ==(Object other) =>
      other is CombinedOrderReadRequest &&
      other.type == type &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(type, filter);
}

final okxExchangePositionsSourceProvider = FutureProvider.autoDispose
    .family<ExchangeRowsResult<ExchangePosition>, String>((ref, filter) async {
      final generation = ref.watch(okxCredentialSnapshotProvider);
      if (generation.rotating) {
        return ExchangeRowsResult<ExchangePosition>.failure(
          source: ExchangeSource.okx,
          product: null,
          error: 'OKX credentials are changing.',
          generation: generation.generation,
        );
      }
      final result = await _readOkxPositions(
        ref,
        ref.watch(okxExchangeReaderProvider),
        filter,
      );
      if (ref.read(okxCredentialSnapshotProvider) != generation) {
        return ExchangeRowsResult<ExchangePosition>.failure(
          source: ExchangeSource.okx,
          product: null,
          error: 'OKX credentials changed while positions were loading.',
          generation: generation.generation,
        );
      }
      return _withRowsGeneration(result, generation.generation);
    });

final binanceExchangePositionsSourceProvider = FutureProvider.autoDispose
    .family<ExchangeRowsResult<ExchangePosition>, String>((ref, filter) async {
      final generation = ref.watch(binanceCredentialSnapshotProvider);
      final reader = ref.watch(binanceExchangeReaderProvider);
      final result = await _readBinancePositions(
        ref,
        reader,
        generation,
        filter,
      );
      if (reader.credentialState.value != generation) {
        return ExchangeRowsResult<ExchangePosition>.failure(
          source: ExchangeSource.binance,
          product: ExchangeProduct.swap,
          error: 'Binance credentials changed while positions were loading.',
          generation: generation.generation,
        );
      }
      return _withRowsGeneration(result, generation.generation);
    });

final combinedExchangePositionsProvider = Provider.autoDispose
    .family<CombinedExchangeRows<ExchangePosition>, String>((ref, filter) {
      final okxGeneration = ref.watch(okxCredentialSnapshotProvider);
      final binanceGeneration = ref.watch(binanceCredentialSnapshotProvider);
      final okx = _rowsFromAsync(
        ref.watch(okxExchangePositionsSourceProvider(filter)),
        ExchangeSource.okx,
        null,
        expectedGeneration: okxGeneration.generation,
        isRotating: okxGeneration.rotating,
      );
      final binance = _rowsFromAsync(
        ref.watch(binanceExchangePositionsSourceProvider(filter)),
        ExchangeSource.binance,
        ExchangeProduct.swap,
        expectedGeneration: binanceGeneration.generation,
        isRotating: binanceGeneration.rotating,
      );
      return CombinedExchangeRows<ExchangePosition>(
        sources: <ExchangeRowsResult<ExchangePosition>>[okx, binance],
      );
    });

Future<ExchangeRowsResult<ExchangePosition>> _readOkxPositions(
  Ref ref,
  OkxExchangeReader reader,
  String filter,
) async {
  try {
    final rows = await runOkxPrivateRead<List<ExchangePosition>>(
      ref: ref,
      requestKey: 'orders/combined/positions/$filter',
      load: (cancelToken) =>
          reader.getOpenPositions(instType: filter, cancelToken: cancelToken),
    );
    return ExchangeRowsResult<ExchangePosition>.success(
      source: ExchangeSource.okx,
      product: null,
      rows: rows,
    );
  } catch (error) {
    return ExchangeRowsResult<ExchangePosition>.failure(
      source: ExchangeSource.okx,
      product: null,
      error: _safeReadError(error),
      isTerminalFailure: _isTerminalReadFailure(error),
    );
  }
}

Future<ExchangeRowsResult<ExchangePosition>> _readBinancePositions(
  Ref ref,
  BinanceExchangeReader reader,
  BinanceCredentialSnapshot generation,
  String filter,
) async {
  if (filter == 'SPOT' || filter == 'MARGIN') {
    return const ExchangeRowsResult<ExchangePosition>.notApplicable(
      source: ExchangeSource.binance,
      product: ExchangeProduct.swap,
    );
  }
  final cancelToken = CancelToken();
  ref.onDispose(() {
    if (!cancelToken.isCancelled) cancelToken.cancel('Position view disposed.');
  });
  try {
    final issues = <ExchangeReadIssue>[];
    final rows = await reader.getFuturesPositions(
      cancelToken: cancelToken,
      expectedGeneration: generation,
      issues: issues,
    );
    final filtered = rows
        .where((position) {
          if (filter == 'ALL') return true;
          return position.product?.name.toUpperCase() == filter;
        })
        .toList(growable: false);
    return ExchangeRowsResult<ExchangePosition>.success(
      source: ExchangeSource.binance,
      product: filter == 'ALL'
          ? ExchangeProduct.swap
          : _productForFilter(filter),
      rows: filtered,
      isComplete: issues.isEmpty,
      error: issues.isEmpty
          ? null
          : 'Some Binance Futures positions were excluded or have incomplete metadata.',
    );
  } catch (error) {
    return ExchangeRowsResult<ExchangePosition>.failure(
      source: ExchangeSource.binance,
      product: filter == 'ALL'
          ? ExchangeProduct.swap
          : _productForFilter(filter),
      error: _safeReadError(error),
      isTerminalFailure: _isTerminalReadFailure(error),
    );
  }
}

final okxExchangeOrdersSourceProvider = FutureProvider.autoDispose
    .family<ExchangeRowsResult<ExchangeOrder>, CombinedOrderReadRequest>((
      ref,
      request,
    ) async {
      final generation = ref.watch(okxCredentialSnapshotProvider);
      if (generation.rotating) {
        return ExchangeRowsResult<ExchangeOrder>.failure(
          source: ExchangeSource.okx,
          product: null,
          error: 'OKX credentials are changing.',
          generation: generation.generation,
        );
      }
      final result = await _readOkxOrders(
        ref,
        ref.watch(okxExchangeReaderProvider),
        request,
      );
      if (ref.read(okxCredentialSnapshotProvider) != generation) {
        return ExchangeRowsResult<ExchangeOrder>.failure(
          source: ExchangeSource.okx,
          product: null,
          error: 'OKX credentials changed while orders were loading.',
          generation: generation.generation,
        );
      }
      return _withRowsGeneration(result, generation.generation);
    });

final binanceSpotPendingOrdersSourceProvider = FutureProvider.autoDispose
    .family<ExchangeRowsResult<ExchangeOrder>, String>((ref, filter) async {
      if (filter != 'ALL' && filter != 'SPOT') {
        return const ExchangeRowsResult<ExchangeOrder>.notApplicable(
          source: ExchangeSource.binance,
          product: ExchangeProduct.spot,
        );
      }
      final generation = ref.watch(binanceCredentialSnapshotProvider);
      final reader = ref.watch(binanceExchangeReaderProvider);
      final token = CancelToken();
      ref.onDispose(() {
        if (!token.isCancelled) token.cancel('Pending Spot view disposed.');
      });
      try {
        final rows = await reader.getSpotOpenOrders(
          cancelToken: token,
          expectedGeneration: generation,
        );
        if (reader.credentialState.value != generation) {
          return ExchangeRowsResult<ExchangeOrder>.failure(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
            error: 'Binance credentials changed while orders were loading.',
            generation: generation.generation,
          );
        }
        return ExchangeRowsResult<ExchangeOrder>.success(
          source: ExchangeSource.binance,
          product: ExchangeProduct.spot,
          rows: rows,
          generation: generation.generation,
        );
      } catch (error) {
        return ExchangeRowsResult<ExchangeOrder>.failure(
          source: ExchangeSource.binance,
          product: ExchangeProduct.spot,
          error: _safeReadError(error),
          isTerminalFailure: _isTerminalReadFailure(error),
          generation: generation.generation,
        );
      }
    });

final binanceFuturesPendingOrdersSourceProvider = FutureProvider.autoDispose
    .family<ExchangeRowsResult<ExchangeOrder>, String>((ref, filter) async {
      if (filter != 'ALL' && filter != 'SWAP' && filter != 'FUTURES') {
        return const ExchangeRowsResult<ExchangeOrder>.notApplicable(
          source: ExchangeSource.binance,
          product: ExchangeProduct.swap,
        );
      }
      final generation = ref.watch(binanceCredentialSnapshotProvider);
      final reader = ref.watch(binanceExchangeReaderProvider);
      final token = CancelToken();
      ref.onDispose(() {
        if (!token.isCancelled) token.cancel('Pending Futures view disposed.');
      });
      try {
        final rows = await reader.getFuturesOpenOrders(
          cancelToken: token,
          expectedGeneration: generation,
        );
        if (reader.credentialState.value != generation) {
          return ExchangeRowsResult<ExchangeOrder>.failure(
            source: ExchangeSource.binance,
            product: ExchangeProduct.swap,
            error: 'Binance credentials changed while orders were loading.',
            generation: generation.generation,
          );
        }
        return ExchangeRowsResult<ExchangeOrder>.success(
          source: ExchangeSource.binance,
          product: ExchangeProduct.swap,
          rows: _filterBinanceOrders(rows, filter),
          generation: generation.generation,
        );
      } catch (error) {
        return ExchangeRowsResult<ExchangeOrder>.failure(
          source: ExchangeSource.binance,
          product: ExchangeProduct.swap,
          error: _safeReadError(error),
          isTerminalFailure: _isTerminalReadFailure(error),
          generation: generation.generation,
        );
      }
    });

final combinedExchangeOrdersProvider = Provider.autoDispose
    .family<CombinedExchangeRows<ExchangeOrder>, CombinedOrderReadRequest>((
      ref,
      request,
    ) {
      final okxGeneration = ref.watch(okxCredentialSnapshotProvider);
      final binanceGeneration = ref.watch(binanceCredentialSnapshotProvider);
      final okx = _rowsFromAsync(
        ref.watch(okxExchangeOrdersSourceProvider(request)),
        ExchangeSource.okx,
        null,
        expectedGeneration: okxGeneration.generation,
        isRotating: okxGeneration.rotating,
      );
      if (request.type == CombinedOrderReadType.history) {
        final history = ref.watch(binanceAccountHistoryProvider);
        return CombinedExchangeRows<ExchangeOrder>(
          sources: <ExchangeRowsResult<ExchangeOrder>>[
            okx,
            _historySourceResult(
              source: ExchangeSource.binance,
              product: ExchangeProduct.spot,
              progress: history.spot,
              error: history.spotError,
              generation: history.generation,
              expectedGeneration: binanceGeneration.generation,
              applies: request.filter == 'ALL' || request.filter == 'SPOT',
            ),
            _historySourceResult(
              source: ExchangeSource.binance,
              product: ExchangeProduct.swap,
              progress: history.futures,
              error: history.futuresError,
              generation: history.generation,
              expectedGeneration: binanceGeneration.generation,
              applies:
                  request.filter == 'ALL' ||
                  request.filter == 'SWAP' ||
                  request.filter == 'FUTURES',
              filter: request.filter,
            ),
          ],
        );
      }
      final spot = _rowsFromAsync(
        ref.watch(binanceSpotPendingOrdersSourceProvider(request.filter)),
        ExchangeSource.binance,
        ExchangeProduct.spot,
        expectedGeneration: binanceGeneration.generation,
        isRotating: binanceGeneration.rotating,
      );
      final futures = _rowsFromAsync(
        ref.watch(binanceFuturesPendingOrdersSourceProvider(request.filter)),
        ExchangeSource.binance,
        ExchangeProduct.swap,
        expectedGeneration: binanceGeneration.generation,
        isRotating: binanceGeneration.rotating,
      );
      return CombinedExchangeRows<ExchangeOrder>(
        sources: <ExchangeRowsResult<ExchangeOrder>>[okx, spot, futures],
      );
    });

void invalidateCombinedExchangePositionSources(Ref ref, String filter) {
  ref.invalidate(okxExchangePositionsSourceProvider(filter));
  if (filter != 'SPOT' && filter != 'MARGIN') {
    ref.invalidate(binanceExchangePositionsSourceProvider(filter));
  }
}

void invalidateCombinedExchangeOrderSources(
  Ref ref,
  CombinedOrderReadRequest request,
) {
  ref.invalidate(okxExchangeOrdersSourceProvider(request));
  if (request.type != CombinedOrderReadType.pending) return;
  if (request.filter == 'ALL' || request.filter == 'SPOT') {
    ref.invalidate(binanceSpotPendingOrdersSourceProvider(request.filter));
  }
  if (request.filter == 'ALL' ||
      request.filter == 'SWAP' ||
      request.filter == 'FUTURES') {
    ref.invalidate(binanceFuturesPendingOrdersSourceProvider(request.filter));
  }
}

ExchangeRowsResult<T> _withRowsGeneration<T>(
  ExchangeRowsResult<T> result,
  int generation,
) => ExchangeRowsResult<T>(
  source: result.source,
  product: result.product,
  rows: result.rows,
  isApplicable: result.isApplicable,
  isComplete: result.isComplete,
  error: result.error,
  isTerminalFailure: result.isTerminalFailure,
  isLoading: result.isLoading,
  generation: generation,
);

ExchangeRowsResult<T> _rowsFromAsync<T>(
  AsyncValue<ExchangeRowsResult<T>> value,
  ExchangeSource source,
  ExchangeProduct? product, {
  required int expectedGeneration,
  required bool isRotating,
}) {
  if (value.isLoading) {
    final previous = value.valueOrNull;
    if (!isRotating && previous?.generation == expectedGeneration) {
      final retained = previous!;
      return ExchangeRowsResult<T>(
        source: retained.source,
        product: retained.product,
        rows: retained.rows,
        isApplicable: retained.isApplicable,
        isComplete: retained.isComplete,
        error: retained.error,
        isTerminalFailure: retained.isTerminalFailure,
        isLoading: true,
        generation: retained.generation,
      );
    }
    return ExchangeRowsResult<T>.loading(
      source: source,
      product: product,
      generation: expectedGeneration,
    );
  }
  if (value.hasError) {
    return ExchangeRowsResult<T>.failure(
      source: source,
      product: product,
      error: _safeReadError(value.error as Object),
      isTerminalFailure: _isTerminalReadFailure(value.error!),
      generation: expectedGeneration,
    );
  }
  return value.requireValue;
}

ExchangeRowsResult<ExchangeOrder> _historySourceResult({
  required ExchangeSource source,
  required ExchangeProduct product,
  required BinanceHistoryScanProgress? progress,
  required String? error,
  required int generation,
  required int expectedGeneration,
  required bool applies,
  String filter = 'ALL',
}) {
  if (!applies) {
    return ExchangeRowsResult<ExchangeOrder>.notApplicable(
      source: source,
      product: product,
    );
  }
  if (generation != expectedGeneration || progress == null && error == null) {
    return ExchangeRowsResult<ExchangeOrder>.loading(
      source: source,
      product: product,
      generation: expectedGeneration,
    );
  }
  final rows = (progress?.rows ?? const <ExchangeOrder>[])
      .where((order) {
        if (filter == 'ALL' || product == ExchangeProduct.spot) return true;
        return order.product?.name.toUpperCase() == filter;
      })
      .toList(growable: false);
  final complete =
      error == null && progress?.allCapturedSymbolsComplete == true;
  return ExchangeRowsResult<ExchangeOrder>.success(
    source: source,
    product: product,
    rows: rows,
    isComplete: complete,
    isLoading: progress?.state == BinanceHistoryScanState.running,
    error:
        error ??
        (complete ? null : progress?.message ?? progress?.coverageNotice),
    generation: generation,
  );
}

Future<ExchangeRowsResult<ExchangeOrder>> _readOkxOrders(
  Ref ref,
  OkxExchangeReader reader,
  CombinedOrderReadRequest request,
) async {
  try {
    final rows = await runOkxPrivateRead<List<ExchangeOrder>>(
      ref: ref,
      requestKey: 'orders/combined/${request.type.name}/${request.filter}',
      load: (cancelToken) => switch (request.type) {
        CombinedOrderReadType.pending => reader.getPendingOrders(
          instType: request.filter,
          cancelToken: cancelToken,
        ),
        CombinedOrderReadType.history => reader.getOrdersHistory(
          instType: request.filter,
          cancelToken: cancelToken,
        ),
        CombinedOrderReadType.positions => Future.value(
          const <ExchangeOrder>[],
        ),
      },
    );
    return ExchangeRowsResult<ExchangeOrder>.success(
      source: ExchangeSource.okx,
      product: null,
      rows: rows,
    );
  } catch (error) {
    return ExchangeRowsResult<ExchangeOrder>.failure(
      source: ExchangeSource.okx,
      product: null,
      error: _safeReadError(error),
      isTerminalFailure: _isTerminalReadFailure(error),
    );
  }
}

List<ExchangeOrder> _filterBinanceOrders(
  Iterable<ExchangeOrder> rows,
  String filter,
) => rows
    .where((order) {
      if (filter == 'ALL') return true;
      return order.product?.name.toUpperCase() == filter;
    })
    .toList(growable: false);

ExchangeProduct? _productForFilter(String filter) => switch (filter) {
  'SPOT' => ExchangeProduct.spot,
  'MARGIN' => ExchangeProduct.margin,
  'SWAP' => ExchangeProduct.swap,
  'FUTURES' => ExchangeProduct.futures,
  _ => null,
};

final binanceAccountHistoryProvider =
    StateNotifierProvider<
      BinanceAccountHistoryController,
      BinanceAccountHistoryState
    >((ref) {
      final reader = ref.watch(binanceExchangeReaderProvider);
      final service = ref.watch(binanceHistoryScanProvider);
      final controller = BinanceAccountHistoryController(reader, service);
      ref.onDispose(controller.dispose);
      return controller;
    });

@immutable
class BinanceAccountHistoryState {
  const BinanceAccountHistoryState({
    this.generation = 0,
    this.spot,
    this.futures,
    this.spotError,
    this.futuresError,
  });

  final int generation;
  final BinanceHistoryScanProgress? spot;
  final BinanceHistoryScanProgress? futures;
  final String? spotError;
  final String? futuresError;

  BinanceAccountHistoryState copyWith({
    int? generation,
    BinanceHistoryScanProgress? spot,
    BinanceHistoryScanProgress? futures,
    String? spotError,
    String? futuresError,
    bool clearSpot = false,
    bool clearFutures = false,
    bool clearSpotError = false,
    bool clearFuturesError = false,
  }) => BinanceAccountHistoryState(
    generation: generation ?? this.generation,
    spot: clearSpot ? null : spot ?? this.spot,
    futures: clearFutures ? null : futures ?? this.futures,
    spotError: clearSpotError ? null : spotError ?? this.spotError,
    futuresError: clearFuturesError ? null : futuresError ?? this.futuresError,
  );
}

class BinanceAccountHistoryController
    extends StateNotifier<BinanceAccountHistoryState> {
  BinanceAccountHistoryController(this._reader, this._service)
    : super(const BinanceAccountHistoryState()) {
    _observedGeneration = _reader.credentialState.value;
    state = state.copyWith(generation: _observedGeneration.generation);
    _reader.credentialState.addListener(_onCredentialChanged);
  }

  final BinanceExchangeReader _reader;
  final BinanceHistoryScanService _service;
  late BinanceCredentialSnapshot _observedGeneration;
  BinanceHistoryScanSession? _spotSession;
  BinanceHistoryScanSession? _futuresSession;
  StreamSubscription<BinanceHistoryScanProgress>? _spotSubscription;
  StreamSubscription<BinanceHistoryScanProgress>? _futuresSubscription;
  Timer? _throttleTimer;
  BinanceHistoryScanProgress? _pendingSpot;
  BinanceHistoryScanProgress? _pendingFutures;
  DateTime _lastPublished = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  void enterHistory() {
    _enterProduct(ExchangeProduct.spot);
    _enterProduct(ExchangeProduct.swap);
  }

  void refreshHistory() {
    _startProduct(ExchangeProduct.spot);
    _startProduct(ExchangeProduct.swap);
  }

  void resumeHistory() {
    if (_spotSession == null) {
      _startProduct(ExchangeProduct.spot);
    } else {
      _resumeProduct(ExchangeProduct.spot);
    }
    if (_futuresSession == null) {
      _startProduct(ExchangeProduct.swap);
    } else {
      _resumeProduct(ExchangeProduct.swap);
    }
  }

  void leaveHistory() {
    _spotSession?.cancel();
    _futuresSession?.cancel();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reader.credentialState.removeListener(_onCredentialChanged);
    _throttleTimer?.cancel();
    unawaited(_spotSubscription?.cancel());
    unawaited(_futuresSubscription?.cancel());
    _spotSession?.cancel();
    _futuresSession?.cancel();
    _spotSession?.dispose();
    _futuresSession?.dispose();
    super.dispose();
  }

  void _enterProduct(ExchangeProduct product) {
    final session = _sessionFor(product);
    if (session == null) {
      _startProduct(product);
      return;
    }
    switch (session.current.state) {
      case BinanceHistoryScanState.running:
        return;
      case BinanceHistoryScanState.complete:
      case BinanceHistoryScanState.failed:
      case BinanceHistoryScanState.idle:
        _startProduct(product);
      case BinanceHistoryScanState.paused:
      case BinanceHistoryScanState.cancelled:
        _resumeProduct(product);
    }
  }

  void _startProduct(ExchangeProduct product) {
    _dropProduct(product);
    try {
      final session = product == ExchangeProduct.spot
          ? _service.startSpotScan()
          : _service.startFuturesScan();
      _setSession(product, session);
      _listen(product, session);
      _publishProgress(product, session.current, immediate: true);
      unawaited(session.run());
    } catch (error) {
      _publishError(product, _safeReadError(error));
    }
  }

  void _resumeProduct(ExchangeProduct product) {
    final session = _sessionFor(product);
    if (session == null) {
      _startProduct(product);
      return;
    }
    _publishProgress(product, session.current, immediate: true);
    unawaited(session.resume(retryFailed: true));
  }

  void _listen(ExchangeProduct product, BinanceHistoryScanSession session) {
    final subscription = session.progress.listen((progress) {
      if (_reader.credentialState.value != _observedGeneration) return;
      final immediate = progress.state != BinanceHistoryScanState.running;
      _publishProgress(product, progress, immediate: immediate);
    });
    if (product == ExchangeProduct.spot) {
      _spotSubscription = subscription;
    } else {
      _futuresSubscription = subscription;
    }
  }

  void _publishProgress(
    ExchangeProduct product,
    BinanceHistoryScanProgress progress, {
    required bool immediate,
  }) {
    if (_disposed || _reader.credentialState.value != _observedGeneration) {
      return;
    }
    if (product == ExchangeProduct.spot) {
      _pendingSpot = progress;
    } else {
      _pendingFutures = progress;
    }
    final now = DateTime.now();
    final elapsed = now.difference(_lastPublished);
    if (immediate || elapsed >= const Duration(milliseconds: 300)) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      _flushProgress();
      return;
    }
    _throttleTimer ??= Timer(const Duration(milliseconds: 300), _flushProgress);
  }

  void _flushProgress() {
    if (_disposed) return;
    _lastPublished = DateTime.now();
    final spot = _pendingSpot;
    final futures = _pendingFutures;
    _pendingSpot = null;
    _pendingFutures = null;
    state = state.copyWith(
      spot: spot,
      futures: futures,
      clearSpotError: spot != null,
      clearFuturesError: futures != null,
    );
  }

  void _publishError(ExchangeProduct product, String message) {
    if (_disposed) return;
    state = product == ExchangeProduct.spot
        ? state.copyWith(spotError: message, clearSpot: true)
        : state.copyWith(futuresError: message, clearFutures: true);
  }

  void _dropProduct(ExchangeProduct product) {
    if (product == ExchangeProduct.spot) {
      unawaited(_spotSubscription?.cancel());
      _spotSubscription = null;
      _spotSession?.cancel();
      _spotSession?.dispose();
      _spotSession = null;
      state = state.copyWith(clearSpot: true, clearSpotError: true);
    } else {
      unawaited(_futuresSubscription?.cancel());
      _futuresSubscription = null;
      _futuresSession?.cancel();
      _futuresSession?.dispose();
      _futuresSession = null;
      state = state.copyWith(clearFutures: true, clearFuturesError: true);
    }
  }

  BinanceHistoryScanSession? _sessionFor(ExchangeProduct product) =>
      product == ExchangeProduct.spot ? _spotSession : _futuresSession;

  void _setSession(ExchangeProduct product, BinanceHistoryScanSession session) {
    if (product == ExchangeProduct.spot) {
      _spotSession = session;
    } else {
      _futuresSession = session;
    }
  }

  void _onCredentialChanged() {
    final current = _reader.credentialState.value;
    if (current == _observedGeneration) return;
    _observedGeneration = current;
    state = state.copyWith(generation: current.generation);
    _throttleTimer?.cancel();
    _pendingSpot = null;
    _pendingFutures = null;
    _dropProduct(ExchangeProduct.spot);
    _dropProduct(ExchangeProduct.swap);
  }
}

T? _firstOrNull<T>(Iterable<T> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}
