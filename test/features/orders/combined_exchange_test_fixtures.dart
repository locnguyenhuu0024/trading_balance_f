import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:trading_balance_f/core/exchange/binance_exchange_reader.dart';
import 'package:trading_balance_f/core/exchange/binance_history_scan.dart';
import 'package:trading_balance_f/core/exchange/exchange_account_providers.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_readers.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';

typedef OrdersRowsFixture =
    Future<ExchangeRowsResult<ExchangeOrder>> Function(
      CombinedOrderReadRequest request,
    );

typedef PositionsRowsFixture =
    Future<ExchangeRowsResult<ExchangePosition>> Function(String filter);

typedef NativeOrdersFixture =
    Future<List<OkxOrder>> Function(CombinedOrderReadRequest request);

typedef NativePositionsFixture =
    Future<List<OkxPosition>> Function(String filter);

/// Overrides the combined account-view seams with deterministic native OKX
/// fixtures and inert Binance sources for existing UI-focused tests.
List<Override> combinedExchangeOrdersTestOverrides({
  Iterable<OkxOrder> pendingOrders = const <OkxOrder>[],
  Iterable<OkxOrder> historyOrders = const <OkxOrder>[],
  Iterable<OkxPosition> positions = const <OkxPosition>[],
  OrdersRowsFixture? loadOrders,
  PositionsRowsFixture? loadPositions,
  NativeOrdersFixture? loadNativeOrders,
  NativePositionsFixture? loadNativePositions,
  BinanceAccountHistoryState? historyState,
}) {
  final pending = List<OkxOrder>.of(pendingOrders);
  final history = List<OkxOrder>.of(historyOrders);
  final positionRows = List<OkxPosition>.of(positions);
  return <Override>[
    okxExchangeOrdersSourceProvider.overrideWith((ref, request) async {
      if (loadOrders != null) return loadOrders(request);
      if (loadNativeOrders != null) {
        final nativeRows = await loadNativeOrders(request);
        return ExchangeRowsResult<ExchangeOrder>.success(
          source: ExchangeSource.okx,
          product: null,
          rows: nativeRows.map(exchangeOrderFromOkx).toList(),
        );
      }
      final nativeRows = switch (request.type) {
        CombinedOrderReadType.pending => pending,
        CombinedOrderReadType.history => history,
        CombinedOrderReadType.positions => const <OkxOrder>[],
      };
      return ExchangeRowsResult<ExchangeOrder>.success(
        source: ExchangeSource.okx,
        product: null,
        rows: nativeRows.map(exchangeOrderFromOkx).toList(),
      );
    }),
    okxExchangePositionsSourceProvider.overrideWith((ref, filter) async {
      if (loadPositions != null) return loadPositions(filter);
      if (loadNativePositions != null) {
        final nativeRows = await loadNativePositions(filter);
        return ExchangeRowsResult<ExchangePosition>.success(
          source: ExchangeSource.okx,
          product: null,
          rows: nativeRows.map(exchangePositionFromOkx).toList(),
        );
      }
      return ExchangeRowsResult<ExchangePosition>.success(
        source: ExchangeSource.okx,
        product: null,
        rows: positionRows.map(exchangePositionFromOkx).toList(),
      );
    }),
    binanceSpotPendingOrdersSourceProvider.overrideWith(
      (ref, filter) async =>
          const ExchangeRowsResult<ExchangeOrder>.notApplicable(
            source: ExchangeSource.binance,
            product: ExchangeProduct.spot,
          ),
    ),
    binanceFuturesPendingOrdersSourceProvider.overrideWith(
      (ref, filter) async =>
          const ExchangeRowsResult<ExchangeOrder>.notApplicable(
            source: ExchangeSource.binance,
            product: ExchangeProduct.swap,
          ),
    ),
    binanceExchangePositionsSourceProvider.overrideWith(
      (ref, filter) async =>
          const ExchangeRowsResult<ExchangePosition>.notApplicable(
            source: ExchangeSource.binance,
            product: ExchangeProduct.swap,
          ),
    ),
    binanceAccountHistoryProvider.overrideWith((ref) {
      final reader = ref.watch(binanceExchangeReaderProvider);
      final service = ref.watch(binanceHistoryScanProvider);
      final controller = _InertHistoryController(
        reader,
        service,
        historyState ?? _completeEmptyHistoryState(),
      );
      ref.onDispose(controller.dispose);
      return controller;
    }),
  ];
}

ExchangeOrder exchangeOrderFromOkx(OkxOrder native) {
  final createdAt = int.tryParse(native.cTime);
  final quoteCurrency = native.tradeQuoteCcy.isNotEmpty
      ? native.tradeQuoteCcy
      : _quoteAsset(native.instId);
  final notional =
      _amount(native.fillNotionalUsd) ?? _amount(native.notionalUsd);
  final price = _amount(native.px);
  return ExchangeOrder(
    source: ExchangeSource.okx,
    product: _product(native.instType),
    kind: ExchangeOrderKind.ordinary,
    symbol: native.instId,
    nativeId: native.ordId,
    side: native.side,
    status: native.state,
    quantity: _amountValue(native.sz, 'OKX order quantity'),
    executedQuantity: _amountValue(
      native.accFillSz,
      'OKX executed order quantity',
    ),
    quoteAmount: notional == null
        ? const ExchangeValue<ExchangeMoney>.unavailable(
            'OKX order notional was not reported.',
          )
        : ExchangeValue<ExchangeMoney>.available(
            ExchangeMoney.tryParse(notional.text, 'USD')!,
          ),
    createdAtMilliseconds: createdAt,
    price: price == null
        ? const ExchangeValue<ExchangeMoney>.unavailable(
            'OKX order price was not reported.',
          )
        : ExchangeValue<ExchangeMoney>.available(
            ExchangeMoney.tryParse(price.text, quoteCurrency)!,
          ),
    nativeRecord: native,
    okxActionDto: native,
  );
}

ExchangePosition exchangePositionFromOkx(OkxPosition native) {
  final amount = _amount(
    native.signedSize.isNotEmpty
        ? native.signedSize
        : native.pos.isNotEmpty
        ? native.pos
        : native.size,
  );
  final direction = native.direction.isNotEmpty
      ? native.direction
      : native.posSide;
  final side = switch (direction.toLowerCase()) {
    'long' => ExchangePositionSide.long,
    'short' => ExchangePositionSide.short,
    'net' => ExchangePositionSide.net,
    _ => ExchangePositionSide.unknown,
  };
  final pnl = _amount(native.upl);
  final nativeId = native.positionId.isNotEmpty
      ? native.positionId
      : native.identity['positionId']?.toString() ??
            '${native.instId}|${native.posSide}';
  return ExchangePosition(
    source: ExchangeSource.okx,
    product: _product(native.instType),
    symbol: native.instId,
    side: side,
    positionAmount: amount == null
        ? const ExchangeValue<ExchangeAmount>.unavailable(
            'OKX position size was not reported.',
          )
        : ExchangeValue<ExchangeAmount>.available(amount),
    entryPrice: _amountValue(native.avgPx, 'OKX entry price'),
    markPrice: _amountValue(native.markPx, 'OKX mark price'),
    unrealizedPnl: pnl == null
        ? const ExchangeValue<ExchangeMoney>.unavailable(
            'OKX unrealized PnL was not reported.',
          )
        : ExchangeValue<ExchangeMoney>.available(
            ExchangeMoney.tryParse(pnl.text, 'USD')!,
          ),
    marginMode: native.mgnMode.isEmpty
        ? const ExchangeValue<String>.unavailable(
            'OKX margin mode was not reported.',
          )
        : ExchangeValue<String>.available(native.mgnMode),
    leverage: _amountValue(native.lever, 'OKX leverage'),
    marginCurrency: native.marginCurrency.isEmpty
        ? const ExchangeValue<String>.unavailable(
            'OKX margin currency was not reported.',
          )
        : ExchangeValue<String>.available(native.marginCurrency),
    nativeId: nativeId,
    nativeRecord: native,
  );
}

BinanceHistoryScanProgress _completeEmptyProgress(ExchangeProduct product) =>
    BinanceHistoryScanProgress(
      product: product,
      state: BinanceHistoryScanState.complete,
      initialized: true,
      totalSymbols: 0,
      completedSymbols: 0,
      failedSymbols: 0,
      pendingSymbols: 0,
      rows: const <ExchangeOrder>[],
      failures: const <String, ExchangeReadException>{},
      catalogIssues: const <ExchangeReadIssue>[],
      retryAt: null,
      message: null,
      coverageNotice:
          'No Binance history symbols are configured in this fixture.',
    );

BinanceAccountHistoryState _completeEmptyHistoryState() =>
    BinanceAccountHistoryState(
      spot: _completeEmptyProgress(ExchangeProduct.spot),
      futures: _completeEmptyProgress(ExchangeProduct.swap),
    );

class _InertHistoryController extends BinanceAccountHistoryController {
  _InertHistoryController(
    BinanceExchangeReader reader,
    BinanceHistoryScanService service,
    BinanceAccountHistoryState fixtureState,
  ) : super(reader, service) {
    state = fixtureState;
  }

  @override
  void enterHistory() {}

  @override
  void leaveHistory() {}

  @override
  void refreshHistory() {}

  @override
  void resumeHistory() {}
}

ExchangeProduct? _product(String value) => switch (value.toUpperCase()) {
  'SPOT' => ExchangeProduct.spot,
  'MARGIN' => ExchangeProduct.margin,
  'SWAP' => ExchangeProduct.swap,
  'FUTURES' => ExchangeProduct.futures,
  _ => null,
};

String _quoteAsset(String symbol) {
  final parts = symbol.split('-');
  return parts.length > 1 ? parts[1] : 'USD';
}

ExchangeAmount? _amount(String value) => ExchangeAmount.tryParse(value);

ExchangeValue<ExchangeAmount> _amountValue(String value, String field) {
  final amount = _amount(value);
  return amount == null
      ? ExchangeValue<ExchangeAmount>.unavailable('$field was not reported.')
      : ExchangeValue<ExchangeAmount>.available(amount);
}
