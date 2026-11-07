import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/exchanges/binance/binance_cost_basis.dart';
import 'package:trading_balance_f/exchanges/binance/binance_estimated_pnl.dart';
import 'package:trading_balance_f/exchanges/binance/binance_trade_history.dart';

void main() {
  const balance = AssetBalance(
    wallet: 'Spot',
    asset: 'BTC',
    total: '4',
    valueUsdt: '440',
  );
  const cost = CostState(quantity: 1, cost: 100);
  test('coverage, loading, stale, missing and unavailable states', () {
    const view = BinanceCostView(
      symbols: {'Spot:BTCUSDT': BinanceSymbolCost(cost, completed: true)},
    );
    final row = estimatedBalance(view, true, balance)!;
    expect(
      estimatedPnlText(row),
      'Giá vốn TB 100.00 · Ước tính +10.00 USDT (+10.00%) · tính trên 25% lượng',
    );
    expect(estimatedBalance(const BinanceCostView(), false, balance), isNull);
    expect(
      estimatedBalance(const BinanceCostView(), true, balance)!.message,
      'Chưa tính',
    );
    expect(
      estimatedBalance(const BinanceCostView(available: false), true, balance),
      isNull,
    );
    final loading = estimatedBalance(
      const BinanceCostView(
        symbols: {'Spot:BTCUSDT': BinanceSymbolCost(cost, stale: true)},
      ),
      true,
      balance,
    )!;
    expect(estimatedPnlText(loading), contains('Đang tải lịch sử'));
    expect(estimatedPnlText(loading), contains('chưa cập nhật'));
    expect(
      estimatedBalance(
        const BinanceCostView(
          symbols: {
            'Spot:BTCUSDT': BinanceSymbolCost(CostState(), completed: true),
          },
        ),
        true,
        balance,
      )!.message,
      'Chưa đủ dữ liệu giá vốn',
    );
    expect(
      estimatedBalance(
        const BinanceCostView(
          symbols: {
            'Spot:BTCUSDT': BinanceSymbolCost(
              CostState(quantity: .001, cost: .1),
              completed: true,
            ),
          },
        ),
        true,
        balance,
      )!.message,
      'Chưa đủ dữ liệu giá vốn',
    );
    expect(
      estimatedBalance(
        view,
        true,
        const AssetBalance(wallet: 'Spot', asset: 'USDT'),
      ),
      isNull,
    );
  });
  test('full coverage and absent prices and unsupported pairs', () {
    const view = BinanceCostView(
      symbols: {
        'Spot:BTCUSDT': BinanceSymbolCost(
          CostState(quantity: 1, cost: 100),
          completed: true,
        ),
      },
    );
    final full = estimatedBalance(
      view,
      true,
      const AssetBalance(
        wallet: 'Spot',
        asset: 'BTC',
        total: '1',
        valueUsdt: '110',
      ),
    )!;
    expect(
      estimatedPnlText(full),
      'Giá vốn TB 100.00 · Ước tính +10.00 USDT (+10.00%)',
    );
    expect(
      estimatedBalance(
        view,
        true,
        const AssetBalance(wallet: 'Spot', asset: 'BTC', total: '1'),
      )!.message,
      'Chưa đủ dữ liệu giá vốn',
    );
    const nonUsdt = MarginAccountRow(
      key: InstrumentKey(
        exchange: ExchangeId.binance,
        product: 'MARGIN',
        nativeId: 'BTCETH',
        base: 'BTC',
        quote: 'ETH',
      ),
      baseNet: '1',
      indexPrice: '1',
    );
    expect(
      estimatedMargin(view, true, nonUsdt, const AccountSnapshot())!.message,
      'Chưa tính',
    );
  });
  test('margin interest and wallet summary use signed holdings once', () {
    const account = AccountSnapshot(
      balances: [
        balance,
        AssetBalance(
          wallet: 'Cross Margin',
          asset: 'BTC',
          net: '-1',
          valueUsdt: '-90',
          interest: '.01',
        ),
      ],
      marginRows: [
        MarginAccountRow(asset: 'BTC', net: '-1', interest: '.01'),
        MarginAccountRow(
          key: InstrumentKey(
            exchange: ExchangeId.binance,
            product: 'MARGIN',
            nativeId: 'BTCUSDT',
            base: 'BTC',
            quote: 'USDT',
          ),
          baseNet: '-1',
          indexPrice: '90',
          baseInterest: '.005',
          quoteInterest: '.45',
        ),
      ],
    );
    const view = BinanceCostView(
      symbols: {
        'Spot:BTCUSDT': BinanceSymbolCost(cost, completed: true),
        'Cross Margin:BTCUSDT': BinanceSymbolCost(
          CostState(quantity: -1, cost: 99.9, isMargin: true),
          completed: true,
        ),
        'Isolated Margin:BTCUSDT': BinanceSymbolCost(
          CostState(quantity: -1, cost: 99.9, isMargin: true),
          completed: true,
        ),
      },
    );
    expect(
      estimatedMargin(
        view,
        true,
        account.marginRows.first,
        account,
      )!.estimate!.profit,
      closeTo(9, .0001),
    );
    expect(
      estimatedMargin(
        view,
        true,
        account.marginRows.last,
        account,
      )!.estimate!.profit,
      closeTo(9, .0001),
    );
    final summary = estimatedSummary(view, true, account);
    expect(summary.eligible, 3);
    expect(summary.covered, 3);
    expect(summary.profit, closeTo(28, .0001));
  });
}
