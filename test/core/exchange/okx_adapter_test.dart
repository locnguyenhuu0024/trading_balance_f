import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/scoped_read.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';

void main() {
  test('OKX adapter maps fixture text and retains native records', () async {
    const account = OkxAccountData(
      details: [
        OkxCoinDetail(
          ccy: 'BTC',
          eq: '0.00100',
          availBal: '0.0005',
          frozenBal: '0.00050',
          upl: '-1.200',
          eqUsd: '80.00',
        ),
      ],
    );
    const position = OkxPosition(
      instId: 'BTC-USDT-SWAP',
      instType: 'SWAP',
      posSide: 'long',
      pos: '0.10',
      size: '0.10',
      avgPx: '10.00',
      markPx: '11.00',
      liqPx: '3',
      lever: '5',
      upl: '1.0',
      uplRatio: '0.1',
      mgnMode: 'cross',
      notionalUsd: '11',
      positionId: 'p',
      positionCurrency: 'BTC',
      marginCurrency: 'USDT',
    );
    const order = OkxOrder(
      instId: 'BTC-USDT',
      instType: 'SPOT',
      ordId: 'o',
      ordType: 'limit',
      side: 'buy',
      px: '12.00',
      sz: '0.20',
      accFillSz: '0.10',
      avgPx: '11.90',
      notionalUsd: '2.4',
      fillNotionalUsd: '1.19',
      lever: '1',
      state: 'live',
      cTime: '1700000000000',
    );
    const scope = ExchangeScope(
      connectionId: 'okx-default',
      exchange: ExchangeId.okx,
      credentialGeneration: 0,
      switchEpoch: 0,
    );
    final container = ProviderContainer(
      overrides: [
        portfolioFutureProvider.overrideWith((ref) async => account),
        positionsFutureProvider.overrideWith((ref) async => [position]),
        ordersFutureProvider.overrideWith((ref) async => [order]),
      ],
    );
    addTearDown(container.dispose);
    final a = await container.read(scopedAccountProvider(scope).future);
    final p = (await container.read(
      scopedPositionsProvider(scope).future,
    )).single;
    final o = (await container.read(scopedOrdersProvider(scope).future)).single;
    expect(a.balances.single.total, '0.00100');
    expect(a.balances.single.available, '0.0005');
    expect(a.balances.single.frozen, '0.00050');
    expect(a.balances.single.unrealizedPnl, '-1.200');
    expect(a.balances.single.valueUsdt, '80.00');
    expect(p.key.nativeId, 'BTC-USDT-SWAP');
    expect(p.entry, '10.00');
    expect(p.size, '0.10');
    expect(p.positionCurrency, 'BTC');
    expect(identical(p.native, position), isTrue);
    expect(o.id, 'o');
    expect(o.price, '12.00');
    expect(o.filled, '0.10');
    expect(o.createdAtMs, '1700000000000');
    expect(identical(o.native, order), isTrue);
  });
}
