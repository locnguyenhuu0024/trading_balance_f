import 'exchange_models.dart';

abstract interface class ExchangeReader {
  ExchangeSource get source;
}

class ExchangeReadException implements Exception {
  const ExchangeReadException({
    required this.code,
    required this.message,
    this.instrument,
    this.retryAt,
    this.statusCode,
  });

  final String code;
  final String message;
  final String? instrument;
  final DateTime? retryAt;
  final int? statusCode;

  @override
  String toString() => '$code: $message';
}

/// Joins an algo parent to an execution only when its positive
/// `actualOrderId` matches an ordinary row on the same source, product and
/// symbol. Numeric ID collisions across kinds or instruments never link.
List<ExchangeOrder> linkConditionalExecutions(Iterable<ExchangeOrder> orders) {
  final rows = orders.toList(growable: false);
  final ordinaryByKey = <String, ExchangeOrder>{};
  for (final order in rows) {
    if (order.kind == ExchangeOrderKind.ordinary) {
      ordinaryByKey.putIfAbsent(_ordinaryLookupKey(order), () => order);
    }
  }

  final linkedParents = <String, ExchangeOrder>{};
  final suppressedConditionalKeys = <String>{};
  for (final conditional in rows) {
    if (conditional.kind != ExchangeOrderKind.conditional) continue;
    final actualOrderId = _positiveId(conditional.actualOrderId);
    if (actualOrderId == null) continue;
    final lookupKey = _ordinaryLookupKey(conditional, orderId: actualOrderId);
    final ordinary = ordinaryByKey[lookupKey];
    if (ordinary == null) continue;
    linkedParents.putIfAbsent(ordinary.identityKey, () => conditional);
    suppressedConditionalKeys.add(conditional.identityKey);
  }

  final result = <ExchangeOrder>[];
  for (final order in rows) {
    if (order.kind == ExchangeOrderKind.conditional &&
        suppressedConditionalKeys.contains(order.identityKey)) {
      continue;
    }
    final parent = linkedParents[order.identityKey];
    if (parent == null) {
      result.add(order);
      continue;
    }
    result.add(
      ExchangeOrder(
        source: order.source,
        product: order.product,
        kind: order.kind,
        symbol: order.symbol,
        nativeId: order.nativeId,
        side: order.side,
        status: order.status,
        quantity: order.quantity,
        executedQuantity: order.executedQuantity,
        quoteAmount: order.quoteAmount,
        createdAtMilliseconds: order.createdAtMilliseconds,
        updatedAtMilliseconds: order.updatedAtMilliseconds,
        price: order.price,
        actualOrderId: order.actualOrderId,
        conditionalParentId: parent.nativeId,
        conditionalParent: parent,
        countsTowardExecution: order.countsTowardExecution,
        nativeRecord: order.nativeRecord,
        okxActionDto: order.okxActionDto,
      ),
    );
  }
  return result;
}

String _ordinaryLookupKey(ExchangeOrder order, {String? orderId}) => <String>[
  order.source.name,
  order.product?.name ?? 'unknown',
  order.symbol,
  _positiveId(orderId ?? order.nativeId) ?? (orderId ?? order.nativeId),
].join('|');

String? _positiveId(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final id = BigInt.tryParse(value.trim());
  return id == null || id <= BigInt.zero ? null : id.toString();
}
