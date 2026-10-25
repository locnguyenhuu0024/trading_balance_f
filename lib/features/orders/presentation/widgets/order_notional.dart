import 'package:flutter/foundation.dart';

import '../../../../core/exchange/exchange_models.dart';
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
  const TradeNotional({
    required this.usdAmount,
    required this.source,
    this.currency = 'USD',
  });

  /// Kept for existing OKX display callers; [currency] is the actual unit.
  final double usdAmount;
  final TradeNotionalSource source;
  final String currency;
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

TradeNotional? resolveExchangeOrderNotional(
  ExchangeOrder order, {
  required bool pending,
}) {
  if (order.source == ExchangeSource.okx && order.okxActionDto is OkxOrder) {
    return resolveOrderNotional(order.okxActionDto as OkxOrder);
  }
  if (!order.countsTowardExecution) return null;
  final filled = order.quoteAmount.value;
  if (!pending && filled != null) {
    final amount = filled.amount.finiteDouble;
    if (amount != null && amount > 0) {
      return TradeNotional(
        usdAmount: amount,
        source: TradeNotionalSource.filledOrder,
        currency: filled.currency,
      );
    }
  }

  final price = order.price?.value;
  final priceAmount = price?.amount.finiteDouble;
  final quantity = pending
      ? order.quantity.value
      : order.executedQuantity.value;
  final quantityAmount = quantity?.finiteDouble;
  if (price == null ||
      priceAmount == null ||
      priceAmount <= 0 ||
      quantityAmount == null ||
      quantityAmount <= 0) {
    return null;
  }
  final notional = priceAmount * quantityAmount;
  if (!notional.isFinite || notional <= 0) return null;
  return TradeNotional(
    usdAmount: notional,
    source: pending
        ? TradeNotionalSource.orderEstimate
        : TradeNotionalSource.filledOrder,
    currency: price.currency,
  );
}

double? _parsePositiveAmount(String value) {
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed == 0) return null;
  return parsed.abs();
}
