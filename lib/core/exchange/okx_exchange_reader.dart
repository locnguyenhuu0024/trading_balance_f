import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/orders/data/okx_order_model.dart';
import '../../features/orders/data/okx_position_model.dart';
import '../../features/orders/data/order_repository.dart';
import '../../features/portfolio/data/portfolio_repository.dart';
import 'exchange_models.dart';
import 'exchange_readers.dart';

final okxExchangeReaderProvider = Provider<OkxExchangeReader>((ref) {
  return OkxExchangeReader(
    portfolioRepository: ref.watch(portfolioRepositoryProvider),
    orderRepository: ref.watch(orderRepositoryProvider),
  );
});

/// Neutral read-only adapter around the existing OKX repositories. The
/// original DTO remains attached so existing OKX action provenance survives.
class OkxExchangeReader implements ExchangeReader {
  const OkxExchangeReader({
    required PortfolioRepository portfolioRepository,
    required OrderRepository orderRepository,
  }) : _portfolioRepository = portfolioRepository,
       _orderRepository = orderRepository;

  final PortfolioRepository _portfolioRepository;
  final OrderRepository _orderRepository;

  @override
  ExchangeSource get source => ExchangeSource.okx;

  Future<ExchangeAccountSnapshot> getAccountBalance({
    CancelToken? cancelToken,
  }) async {
    final account = await _portfolioRepository.getAccountBalance(
      cancelToken: cancelToken,
    );
    final balances = <ExchangeBalance>[];
    final issues = <ExchangeReadIssue>[];
    for (final detail in account.details) {
      final asset = _assetCode(detail.ccy);
      if (asset == null) {
        issues.add(
          const ExchangeReadIssue(
            code: 'okx_invalid_balance_asset',
            message: 'An OKX balance asset was unavailable.',
          ),
        );
        continue;
      }
      final free = _amountValue(detail.availBal, 'OKX available balance');
      final locked = _amountValue(detail.frozenBal, 'OKX frozen balance');
      final total = _amountValue(detail.cashBal, 'OKX cash balance');
      final usdValue = _moneyValue(detail.eqUsd, 'USD', 'OKX USD equity');
      if (!free.isAvailable || !locked.isAvailable || !total.isAvailable) {
        issues.add(
          ExchangeReadIssue(
            code: 'okx_invalid_balance_amount',
            message: 'An OKX balance amount was unavailable.',
            instrument: asset,
          ),
        );
      }
      balances.add(
        ExchangeBalance(
          source: ExchangeSource.okx,
          product: null,
          wallet: 'unified',
          asset: asset,
          free: free,
          locked: locked,
          reportedTotal: total,
          reportedUsdValue: usdValue,
          nativeRecord: detail,
        ),
      );
    }
    return ExchangeAccountSnapshot(
      source: ExchangeSource.okx,
      product: null,
      generation: 0,
      balances: balances,
      reportedEquity: _moneyValue(account.totalEq, 'USD', 'OKX account equity'),
      unrealizedPnl: const ExchangeValue.unavailable(
        'OKX account equity is reported natively by the account reader.',
      ),
      equityIncludesUnrealizedPnl: true,
      issues: issues,
      nativeRecord: account,
    );
  }

  Future<List<ExchangeOrder>> getPendingOrders({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    final orders = await _orderRepository.getPendingOrders(
      instType: instType,
      cancelToken: cancelToken,
    );
    return List<ExchangeOrder>.unmodifiable(orders.map(_order));
  }

  Future<List<ExchangeOrder>> getOrdersHistory({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    final orders = await _orderRepository.getOrdersHistory(
      instType: instType,
      cancelToken: cancelToken,
    );
    return List<ExchangeOrder>.unmodifiable(orders.map(_order));
  }

  Future<List<ExchangePosition>> getOpenPositions({
    String instType = 'ALL',
    CancelToken? cancelToken,
  }) async {
    final positions = await _orderRepository.getOpenPositions(
      instType: instType,
      cancelToken: cancelToken,
    );
    return List<ExchangePosition>.unmodifiable(
      positions.where(_isNonZero).map(_position),
    );
  }

  ExchangeOrder _order(OkxOrder order) {
    final product = _product(order.instType);
    final symbol = order.instId.trim();
    return ExchangeOrder(
      source: ExchangeSource.okx,
      product: product,
      kind: ExchangeOrderKind.ordinary,
      symbol: symbol,
      nativeId: order.ordId,
      side: order.side.toLowerCase(),
      status: order.state,
      quantity: _amountValue(order.sz, 'OKX order quantity'),
      executedQuantity: _amountValue(order.accFillSz, 'OKX executed quantity'),
      quoteAmount: _moneyValue(
        order.fillNotionalUsd,
        'USD',
        'OKX filled notional',
      ),
      createdAtMilliseconds: int.tryParse(order.cTime),
      price: _moneyValue(order.px, _quoteAsset(symbol), 'OKX order price'),
      nativeRecord: order,
      okxActionDto: order,
    );
  }

  ExchangePosition _position(OkxPosition position) {
    final side = switch (position.posSide.toLowerCase()) {
      'long' => ExchangePositionSide.long,
      'short' => ExchangePositionSide.short,
      'net' => ExchangePositionSide.net,
      _ => ExchangePositionSide.unknown,
    };
    final rawAmount = position.signedSize.isNotEmpty
        ? position.signedSize
        : position.pos;
    final marginCurrency = _assetCode(position.marginCurrency);
    return ExchangePosition(
      source: ExchangeSource.okx,
      product: _product(position.instType),
      symbol: position.instId,
      side: side,
      positionAmount: _amountValue(rawAmount, 'OKX position size'),
      entryPrice: _amountValue(position.avgPx, 'OKX entry price'),
      markPrice: _amountValue(position.markPx, 'OKX mark price'),
      unrealizedPnl: _moneyValue(
        position.upl,
        marginCurrency,
        'OKX unrealized PnL',
      ),
      marginMode: _stringValue(position.mgnMode, 'OKX margin mode'),
      leverage: _amountValue(position.lever, 'OKX leverage'),
      marginCurrency: _stringValue(marginCurrency, 'OKX margin currency'),
      nativeId: position.positionId,
      nativeRecord: position,
    );
  }

  static bool _isNonZero(OkxPosition position) {
    final amount = ExchangeAmount.tryParse(
      position.signedSize.isNotEmpty ? position.signedSize : position.pos,
    );
    return amount != null && !amount.isZero;
  }

  static ExchangeProduct? _product(String instType) =>
      switch (instType.toUpperCase()) {
        'SPOT' => ExchangeProduct.spot,
        'MARGIN' => ExchangeProduct.margin,
        'SWAP' => ExchangeProduct.swap,
        'FUTURES' => ExchangeProduct.futures,
        _ => null,
      };

  static String? _assetCode(String value) {
    final code = value.trim().toUpperCase();
    return RegExp(r'^[A-Z0-9]{1,20}$').hasMatch(code) ? code : null;
  }

  static String? _quoteAsset(String symbol) {
    final parts = symbol.split('-');
    return parts.length >= 2 ? _assetCode(parts[1]) : null;
  }

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
    Object? value,
    String? currency,
    String label,
  ) {
    final money = ExchangeMoney.tryParse(value, currency);
    return money == null
        ? ExchangeValue<ExchangeMoney>.unavailable('$label is unavailable.')
        : ExchangeValue<ExchangeMoney>.available(money);
  }

  static ExchangeValue<String> _stringValue(Object? value, String label) {
    if (value is! String || value.trim().isEmpty) {
      return ExchangeValue<String>.unavailable('$label is unavailable.');
    }
    return ExchangeValue<String>.available(value.trim());
  }
}
