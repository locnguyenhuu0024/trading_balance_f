import 'package:flutter/foundation.dart';

import '../../../../core/exchange/exchange_models.dart';

enum TradeNotionalSource {
  position,
  filledOrder,
  orderEstimate,
  spotMarginFallback,
}

@immutable
class TradeNotional {
  const TradeNotional({required this.usdAmount, required this.source});

  final double usdAmount;
  final TradeNotionalSource source;
}

TradeNotional? resolvePositionNotional(ExchangePosition position) {
  final notional = _parsePositiveAmount(position.notional);
  if (notional == null) return null;

  return TradeNotional(
    usdAmount: notional,
    source: TradeNotionalSource.position,
  );
}

TradeNotional? resolveOrderNotional(ExchangeOrder order) {
  final filledNotional = _parsePositiveAmount(order.filledNotional);
  if (filledNotional != null) {
    return TradeNotional(
      usdAmount: filledNotional,
      source: TradeNotionalSource.filledOrder,
    );
  }

  final estimatedNotional = _parsePositiveAmount(order.notional);
  if (estimatedNotional != null) {
    return TradeNotional(
      usdAmount: estimatedNotional,
      source: TradeNotionalSource.orderEstimate,
    );
  }

  if (order.productLabel != 'SPOT' && order.productLabel != 'MARGIN') {
    return null;
  }

  final price =
      _parsePositiveAmount(order.average) ?? _parsePositiveAmount(order.price);
  final size =
      _parsePositiveAmount(order.filled) ??
      _parsePositiveAmount(order.quantity);
  if (price == null || size == null) return null;

  return TradeNotional(
    usdAmount: price * size,
    source: TradeNotionalSource.spotMarginFallback,
  );
}

double? _parsePositiveAmount(String? value) {
  final parsed = double.tryParse(value ?? '');
  if (parsed == null || !parsed.isFinite || parsed == 0) return null;
  return parsed.abs();
}
