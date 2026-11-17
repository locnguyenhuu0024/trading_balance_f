import 'dart:math' as math;

/// A trade in a base asset quoted in USDT, in chronological order.
class CostTrade {
  const CostTrade({
    required this.id,
    required this.isBuyer,
    required this.quantity,
    required this.quoteQuantity,
    this.commission = 0,
    this.commissionAsset = '',
    required this.baseAsset,
  });

  final int id;
  final bool isBuyer;
  final double quantity;
  final double quoteQuantity;
  final double commission;
  final String commissionAsset;
  final String baseAsset;
}

/// Cost is positive for both a long position and the proceeds of a short.
class CostState {
  const CostState({
    this.quantity = 0,
    this.cost = 0,
    this.lastTradeId,
    this.isMargin = false,
  });

  final double quantity;
  final double cost;
  final int? lastTradeId;
  final bool isMargin;

  factory CostState.fromJson(Map<String, dynamic> json) => CostState(
    quantity: (json['quantity'] as num).toDouble(),
    cost: (json['cost'] as num).toDouble(),
    lastTradeId: json['lastTradeId'] as int?,
    isMargin: json['isMargin'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'cost': cost,
    'lastTradeId': lastTradeId,
    'isMargin': isMargin,
  };

  CostState apply(CostTrade trade) {
    if (!trade.quantity.isFinite ||
        !trade.quoteQuantity.isFinite ||
        !trade.commission.isFinite ||
        trade.quantity <= 0 ||
        trade.quoteQuantity <= 0 ||
        trade.commission < 0) {
      throw ArgumentError('Invalid trade amounts');
    }
    final baseFee = trade.commissionAsset == trade.baseAsset
        ? trade.commission
        : 0.0;
    final quoteFee = trade.commissionAsset == 'USDT' ? trade.commission : 0.0;
    final amount = trade.isBuyer ? trade.quantity - baseFee : trade.quantity;
    final value = trade.isBuyer
        ? trade.quoteQuantity + quoteFee
        : trade.quoteQuantity - quoteFee;
    if (amount <= 0 || value <= 0) {
      throw ArgumentError('Invalid trade after fees');
    }

    final change = trade.isBuyer ? amount : -amount;
    double nextQuantity;
    double nextCost;
    if (quantity == 0 || quantity.sign == change.sign) {
      if (!isMargin && change < 0) {
        nextQuantity = 0;
        nextCost = 0;
      } else {
        nextQuantity = quantity + change;
        nextCost = cost + value;
      }
    } else if (amount < quantity.abs()) {
      nextQuantity = quantity + change;
      nextCost = cost * (nextQuantity.abs() / quantity.abs());
    } else if (!isMargin || amount == quantity.abs()) {
      nextQuantity = 0;
      nextCost = 0;
    } else {
      nextQuantity = quantity + change;
      nextCost = value * (nextQuantity.abs() / amount);
    }
    return CostState(
      quantity: nextQuantity,
      cost: nextCost,
      lastTradeId: trade.id,
      isMargin: isMargin,
    );
  }
}

class CostEstimate {
  const CostEstimate({
    required this.average,
    required this.coveredQuantity,
    required this.ratio,
    required this.profit,
    required this.percentage,
  });

  final double average;
  final double coveredQuantity;
  final double ratio;
  final double profit;

  /// Percentage points, e.g. 25 for 25%.
  final double percentage;
}

/// Returns null when the holding cannot be estimated from this state.
CostEstimate? estimate(
  CostState state,
  double holding,
  double mark,
  double interestInBase,
) {
  if (!holding.isFinite ||
      holding == 0 ||
      !mark.isFinite ||
      mark <= 0 ||
      !interestInBase.isFinite ||
      interestInBase < 0 ||
      !state.quantity.isFinite ||
      state.quantity == 0 ||
      !state.cost.isFinite ||
      state.cost <= 0 ||
      state.quantity.sign != holding.sign) {
    return null;
  }
  final average = state.cost / state.quantity.abs();
  final covered = math.min(state.quantity.abs(), holding.abs());
  final ratio = covered / holding.abs();
  final profit =
      covered * (holding > 0 ? mark - average : average - mark) -
      (state.isMargin ? interestInBase * mark : 0);
  final percentage = profit / (covered * average) * 100;
  if (!average.isFinite ||
      !ratio.isFinite ||
      !profit.isFinite ||
      !percentage.isFinite) {
    return null;
  }
  return CostEstimate(
    average: average,
    coveredQuantity: covered,
    ratio: ratio,
    profit: profit,
    percentage: percentage,
  );
}
