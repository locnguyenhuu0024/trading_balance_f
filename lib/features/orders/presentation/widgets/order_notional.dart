import 'package:flutter/foundation.dart';

import '../../data/okx_order_model.dart';
import '../../data/okx_position_model.dart';

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

TradeNotional? resolvePositionNotional(OkxPosition position) {
  final notional = _parsePositiveAmount(position.notionalUsd);
  if (notional == null) return null;

  return TradeNotional(
    usdAmount: notional,
    source: TradeNotionalSource.position,
  );
}

TradeNotional? resolveOrderNotional(OkxOrder order) {
  final filledNotional = _parsePositiveAmount(order.fillNotionalUsd);
  if (filledNotional != null) {
    return TradeNotional(
      usdAmount: filledNotional,
      source: TradeNotionalSource.filledOrder,
    );
  }

  final estimatedNotional = _parsePositiveAmount(order.notionalUsd);
  if (estimatedNotional != null) {
    return TradeNotional(
      usdAmount: estimatedNotional,
      source: TradeNotionalSource.orderEstimate,
    );
  }

  if (order.instType != 'SPOT' && order.instType != 'MARGIN') {
    return null;
  }

  final price =
      _parsePositiveAmount(order.avgPx) ?? _parsePositiveAmount(order.px);
  final size =
      _parsePositiveAmount(order.accFillSz) ?? _parsePositiveAmount(order.sz);
  if (price == null || size == null) return null;

  return TradeNotional(
    usdAmount: price * size,
    source: TradeNotionalSource.spotMarginFallback,
  );
}

double? _parsePositiveAmount(String value) {
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed == 0) return null;
  return parsed.abs();
}
