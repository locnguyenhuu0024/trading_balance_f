import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_details_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

import '../../support/fake_exchange_adapter.dart';

class _Socket extends OkxWebsocketService {
  int subscriptions = 0;
  @override
  void subscribeToTickers(List<String> coins) => subscriptions++;
  @override
  void clearLegacySubscription() {}
}

class _Fake extends FakeExchangeAdapter {
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async =>
      const AccountSnapshot(
        total: '42',
        balances: [
          AssetBalance(
            wallet: 'fake',
            asset: 'FAKE',
            total: '42',
            valueUsdt: '42',
          ),
        ],
      );
}

class _SnapshotAdapter extends FakeExchangeAdapter {
  _SnapshotAdapter(this.snapshot);
  final AccountSnapshot snapshot;

  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async =>
      snapshot;
}

void main() {
  for (final details in [false, true]) {
    for (final scenario in ['binance', 'no-usdm', 'okx']) {
      testWidgets('PnL scope $scenario ${details ? "details" : "home"}', (
        tester,
      ) async {
        final isOkx = scenario == 'okx';
        final noUsdm = scenario == 'no-usdm';
        final snapshot = AccountSnapshot(
          total: '2000',
          balances: [
            if (!noUsdm)
              const AssetBalance(
                wallet: 'USD-M',
                asset: 'USDT',
                total: '1100',
                valueUsdt: '1100',
                unrealizedPnl: '100',
              ),
            AssetBalance(
              wallet: 'Spot',
              asset: 'OTHER',
              total: noUsdm ? '2000' : '900',
              valueUsdt: noUsdm ? '2000' : '900',
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            selectedConnectionIdProvider.overrideWith((ref) => 'test'),
            exchangeRegistryProvider.overrideWith(
              (ref) => [
                ExchangeRegistration(
                  profile: ConnectionProfile(
                    connectionId: 'test',
                    exchange: isOkx ? ExchangeId.okx : ExchangeId.binance,
                    label: isOkx ? 'OKX' : 'Binance',
                  ),
                  adapter: _SnapshotAdapter(snapshot),
                ),
              ],
            ),
            livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
            okxWebsocketProvider.overrideWithValue(_Socket()),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: details
                  ? const PortfolioDetailsScreen()
                  : const PortfolioScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        if (details) {
          await tester.tap(find.byKey(const Key('portfolio-reveal-pnl')));
          await tester.pump();
        }
        expect(
          find.text(
            details
                ? (isOkx ? 'Unrealized PnL' : 'Unrealized PnL · USDⓈ-M')
                : (isOkx
                      ? 'Lãi / lỗ chưa thực hiện'
                      : 'Lãi / lỗ chưa thực hiện · USDⓈ-M'),
          ),
          findsOneWidget,
        );
        if (noUsdm && details) {
          expect(find.text('******'), findsOneWidget);
        } else {
          expect(
            find.text(
              noUsdm
                  ? '(+0.00%)'
                  : isOkx
                  ? '(+5.26%)'
                  : '(+10.00%)',
            ),
            findsOneWidget,
          );
        }
        if (!noUsdm) expect(find.text(r'$1,900.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
    }
  }
  testWidgets('fake exchange renders balances without starting OKX prices', (
    tester,
  ) async {
    var priceStarts = 0;
    final socket = _Socket();
    final container = ProviderContainer(
      overrides: [
        selectedConnectionIdProvider.overrideWith((ref) => 'fake'),
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'fake',
                exchange: ExchangeId.binance,
                label: 'Fake',
              ),
              adapter: _Fake(),
            ),
          ],
        ),
        livePriceProvider.overrideWith((ref) {
          priceStarts++;
          return LivePriceNotifier();
        }),
        okxWebsocketProvider.overrideWithValue(socket),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
      ],
    );
    addTearDown(container.dispose);
    for (final screen in [
      const PortfolioScreen(),
      const PortfolioDetailsScreen(),
    ]) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('FAKE'), findsOneWidget);
      expect(find.textContaining('42.00'), findsWidgets);
      expect(priceStarts, 0);
      expect(socket.subscriptions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  for (final details in [false, true]) {
    testWidgets(
      'late OKX response never renders under fake exchange ${details ? "details" : "home"}',
      (tester) async {
        final pending = Completer<OkxAccountData>();
        var priceStarts = 0;
        final socket = _Socket();
        final container = ProviderContainer(
          overrides: [
            exchangeRegistryProvider.overrideWith(
              (ref) => [
                const ExchangeRegistration(
                  profile: ConnectionProfile(
                    connectionId: 'okx-default',
                    exchange: ExchangeId.okx,
                    label: 'OKX',
                  ),
                  adapter: OkxAdapter(),
                ),
                ExchangeRegistration(
                  profile: const ConnectionProfile(
                    connectionId: 'fake',
                    exchange: ExchangeId.binance,
                    label: 'Fake',
                  ),
                  adapter: _Fake(),
                ),
              ],
            ),
            portfolioFutureProvider.overrideWith((ref) => pending.future),
            livePriceProvider.overrideWith((ref) {
              priceStarts++;
              return LivePriceNotifier();
            }),
            okxWebsocketProvider.overrideWithValue(socket),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: details
                  ? const PortfolioDetailsScreen()
                  : const PortfolioScreen(),
            ),
          ),
        );
        await tester.pump();
        final beforeSwitchPriceStarts = priceStarts;
        container.read(selectedConnectionIdProvider.notifier).state = 'fake';
        await tester.pump();
        await tester.pump();
        pending.complete(
          const OkxAccountData(
            details: [OkxCoinDetail(ccy: 'LATE', eq: '999', eqUsd: '999')],
          ),
        );
        await tester.pump();
        expect(find.text('FAKE'), findsOneWidget);
        expect(find.textContaining('42.00'), findsWidgets);
        expect(find.text('LATE'), findsNothing);
        expect(find.textContaining('999'), findsNothing);
        expect(socket.subscriptions, 0);
        expect(priceStarts, beforeSwitchPriceStarts);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
