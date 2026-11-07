import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/exchange/exchange_adapter.dart';
import '../../core/exchange/exchange_models.dart';
import '../../core/exchange/market_source.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/network/okx_data_client.dart';
import '../../features/support_resistance/data/market_repository.dart';
import '../../core/network/okx_read_scope.dart';
import '../../features/orders/presentation/providers/order_provider.dart';
import '../../features/portfolio/presentation/providers/portfolio_provider.dart';

class OkxAdapter implements ExchangeAdapter {
  const OkxAdapter();
  @override
  ExchangeId get id => ExchangeId.okx;
  @override
  List<String> get marketProducts => const ['SPOT'];
  @override
  MarketSource market(Ref ref) => SupportResistanceRepository(
    ref.watch(okxDataClientProvider),
    requestCoordinator: ref.watch(exchangeRequestCoordinatorProvider(id)),
  );
  @override
  ExchangeCapabilities get capabilities => const ExchangeCapabilities(
    readableProducts: ['SPOT', 'MARGIN', 'SWAP', 'FUTURES'],
  );
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async {
    final account = await ref.watch(portfolioFutureProvider.future);
    return AccountSnapshot(
      balances: [
        for (final coin in account.details)
          AssetBalance(
            wallet: 'trading',
            asset: coin.ccy,
            total: coin.eq,
            available: coin.availBal,
            frozen: coin.frozenBal,
            unrealizedPnl: coin.upl,
            valueUsdt: coin.eqUsd,
          ),
      ],
    );
  }

  @override
  Future<List<ExchangePosition>> readPositions(
    Ref ref,
    ExchangeScope scope,
  ) async {
    final positions = await ref.watch(positionsFutureProvider.future);
    return [
      for (final p in positions)
        ExchangePosition(
          key: InstrumentKey(
            exchange: id,
            product: p.instType,
            nativeId: p.instId,
          ),
          productLabel: p.instType,
          side: p.posSide,
          direction: p.direction,
          size: p.size,
          entry: p.avgPx,
          mark: p.markPx,
          liquidation: p.liqPx,
          leverage: p.lever,
          marginMode: p.mgnMode,
          unrealizedPnl: p.upl,
          unrealizedPnlRatio: p.uplRatio,
          notional: p.notionalUsd,
          positionId: p.positionId,
          positionCurrency: p.positionCurrency,
          marginCurrency: p.marginCurrency,
          native: p,
        ),
    ];
  }

  @override
  Future<List<ExchangeOrder>> readOrders(Ref ref, ExchangeScope scope) async {
    final orders = await ref.watch(ordersFutureProvider.future);
    return [
      for (final o in orders)
        ExchangeOrder(
          id: o.ordId,
          key: InstrumentKey(
            exchange: id,
            product: o.instType,
            nativeId: o.instId,
          ),
          productLabel: o.instType,
          type: o.ordType,
          side: o.side,
          price: o.px,
          quantity: o.sz,
          filled: o.accFillSz,
          average: o.avgPx,
          notional: o.notionalUsd,
          filledNotional: o.fillNotionalUsd,
          leverage: o.lever,
          state: o.state,
          createdAtMs: o.cTime,
          native: o,
        ),
    ];
  }

  @override
  void invalidateAccount(void Function(ProviderOrFamily) invalidate) =>
      invalidate(portfolioFutureProvider);
  @override
  void invalidatePositions(void Function(ProviderOrFamily) invalidate) =>
      invalidate(positionsFutureProvider);
  @override
  void invalidateOrders(void Function(ProviderOrFamily) invalidate) =>
      invalidate(ordersFutureProvider);
  @override
  ExchangeFailure classify(Object error) {
    if (isOkxReadCancellation(error))
      return const ExchangeFailure(ExchangeFailureKind.cancellation);
    if (isTransientOkxReadFailure(error))
      return ExchangeFailure(
        ExchangeFailureKind.transient,
        retryAfter: okxReadRetryAfter(error, DateTime.now()),
      );
    if (isTerminalOkxReadFailure(error))
      return const ExchangeFailure(ExchangeFailureKind.credential);
    return const ExchangeFailure(ExchangeFailureKind.other);
  }
}
