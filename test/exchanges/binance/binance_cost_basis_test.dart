import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/exchanges/binance/binance_cost_basis.dart';

CostTrade trade(
  int id,
  bool buy,
  double quantity,
  double quote, {
  double fee = 0,
  String feeAsset = '',
}) => CostTrade(
  id: id,
  isBuyer: buy,
  quantity: quantity,
  quoteQuantity: quote,
  commission: fee,
  commissionAsset: feeAsset,
  baseAsset: 'BTC',
);

void main() {
  final spotTrades = [
    trade(1, true, 1, 100, fee: 0.001, feeAsset: 'BTC'),
    trade(2, true, 1, 200, fee: 0.2, feeAsset: 'USDT'),
    trade(3, false, 0.5, 150),
  ];
  CostState applyAll(CostState state, Iterable<CostTrade> trades) =>
      trades.fold(state, (state, trade) => state.apply(trade));

  test('TEST-128-1: Spot moving average and proportional sale', () {
    final state = applyAll(const CostState(), spotTrades);
    final result = estimate(state, 1.499, 250, 0)!;
    expect(state.quantity, closeTo(1.499, 1e-10));
    expect(state.cost, closeTo(225.1125, 0.0001));
    expect(result.average, closeTo(150.1751, 0.0001));
    expect(result.profit, closeTo(149.6375, 0.0001));
    expect(result.percentage, closeTo(66.47, 0.01));
    expect(result.coveredQuantity, closeTo(1.499, 1e-10));
    expect(result.ratio, 1);
  });

  test('TEST-128-2: short proceeds and unpaid interest', () {
    final state = applyAll(const CostState(isMargin: true), [
      trade(1, false, 2, 200, fee: 0.2, feeAsset: 'USDT'),
      trade(2, true, 1, 80),
    ]);
    final beforeInterest = estimate(state, -1, 90, 0)!;
    final result = estimate(state, -1, 90, 0.01)!;
    expect(result.average, closeTo(99.9, 1e-10));
    expect(beforeInterest.profit, closeTo(9.9, 1e-10));
    expect(result.profit, closeTo(9, 1e-10));
    expect(result.percentage, closeTo(9 / 99.9 * 100, 1e-10));
  });

  test('TEST-128-3: coverage is limited to known trades', () {
    final result = estimate(
      const CostState().apply(trade(1, true, 1, 100)),
      4,
      110,
      0,
    )!;
    expect(result.coveredQuantity, 1);
    expect(result.ratio, 0.25);
    expect(result.profit, 10);
    expect(result.percentage, 10);
  });

  test('TEST-128-4: JSON round trip resumes identically in two batches', () {
    final oneBatch = applyAll(const CostState(), spotTrades);
    final firstBatch = applyAll(const CostState(), spotTrades.take(2));
    final restored = CostState.fromJson(
      jsonDecode(jsonEncode(firstBatch.toJson())) as Map<String, dynamic>,
    );
    final twoBatches = applyAll(restored, spotTrades.skip(2));
    expect(twoBatches.toJson(), oneBatch.toJson());
    expect(twoBatches.lastTradeId, 3);
    final margin = const CostState(
      isMargin: true,
    ).apply(trade(4, false, 1, 100));
    expect(
      CostState.fromJson(
        jsonDecode(jsonEncode(margin.toJson())) as Map<String, dynamic>,
      ).toJson(),
      margin.toJson(),
    );
  });

  test('TEST-128-5: excess Spot sale is dropped', () {
    final state = applyAll(const CostState(), [
      trade(1, true, 1, 100),
      trade(2, false, 2, 300),
    ]);
    expect(state.quantity, 0);
    expect(state.cost, 0);
    expect(state.lastTradeId, 2);
  });

  test('TEST-128-5b: Spot sale with no known quantity stays at zero', () {
    final state = const CostState().apply(trade(1, false, 1, 100));
    expect(state.quantity, 0);
    expect(state.cost, 0);
    expect(state.lastTradeId, 1);
  });

  test('TEST-128-6: margin crossing restarts cost at trade price', () {
    final short = applyAll(const CostState(isMargin: true), [
      trade(1, true, 1, 100),
      trade(2, false, 3, 600, fee: 0.6, feeAsset: 'USDT'),
    ]);
    expect(short.quantity, -2);
    expect(short.cost, closeTo(399.6, 1e-10));
    expect(estimate(short, -2, 180, 0)!.average, closeTo(199.8, 1e-10));
    final long = short.apply(trade(3, true, 3, 450));
    expect(long.quantity, 1);
    expect(long.cost, closeTo(150, 1e-10));
  });

  test('TEST-128-7: unavailable or invalid data never yields NaN', () {
    final state = const CostState().apply(trade(1, true, 1, 100));
    expect(estimate(state, -1, 100, 0), isNull);
    expect(estimate(const CostState(), 1, 100, 0), isNull);
    expect(estimate(state, 1, 0, 0), isNull);
    expect(estimate(state, 0, 100, 0), isNull);
    expect(estimate(state, double.nan, 100, 0), isNull);
    expect(estimate(state, 1, double.infinity, 0), isNull);
  });

  test('TEST-128-8: BNB fee is ignored', () {
    final plain = const CostState().apply(trade(1, true, 1, 100));
    final withFee = const CostState().apply(
      trade(1, true, 1, 100, fee: 0.5, feeAsset: 'BNB'),
    );
    expect(withFee.toJson(), plain.toJson());
  });
}
