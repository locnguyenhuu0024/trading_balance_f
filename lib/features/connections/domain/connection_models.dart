import 'package:flutter/foundation.dart';

Map<String, dynamic> connectionJsonMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _string(Object? value) => value is String ? value : '';

DateTime? _date(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : DateTime.tryParse(text)?.toUtc();
}

@immutable
class ConnectionRecord {
  const ConnectionRecord({
    required this.connectionId,
    required this.exchange,
    required this.environment,
    required this.region,
    required this.capabilities,
    required this.nickname,
    required this.status,
    required this.credentialVersion,
    required this.permissionVersion,
    this.verifiedAt,
  });

  final String connectionId;
  final String exchange;
  final String environment;
  final String region;
  final List<String> capabilities;
  final String nickname;
  final String status;
  final int credentialVersion;
  final int permissionVersion;
  final DateTime? verifiedAt;

  bool get isAvailable => const {'ACTIVE', 'RECONCILING'}.contains(status);
  bool get canTrade => capabilities.contains('trade') && status == 'ACTIVE';
  String get displayName => nickname.isNotEmpty ? nickname : exchange;

  factory ConnectionRecord.fromJson(Object? value) {
    final json = connectionJsonMap(value);
    final rawCapabilities = json['capabilities'];
    final capabilities = rawCapabilities is List
        ? rawCapabilities.whereType<String>().toList(growable: false)
        : const <String>[];
    return ConnectionRecord(
      connectionId: _string(json['connectionId']),
      exchange: _string(json['exchange']).toUpperCase(),
      environment: _string(json['environment']).toLowerCase(),
      region: _string(json['region']).toLowerCase(),
      capabilities: List.unmodifiable(capabilities),
      nickname: _string(json['nickname']),
      status: _string(json['status']).toUpperCase(),
      credentialVersion: _int(json['credentialVersion']),
      permissionVersion: _int(json['permissionVersion']),
      verifiedAt: _date(json['verifiedAt']),
    );
  }

  static int _int(Object? value) => value is int ? value : -1;
}

@immutable
class DataMeta {
  const DataMeta({
    this.fetchedAt,
    this.asOf,
    this.snapshotExpiresAt,
    required this.stale,
    required this.complete,
    this.source,
  });

  final DateTime? fetchedAt;
  final DateTime? asOf;
  final DateTime? snapshotExpiresAt;
  final bool stale;
  final bool complete;
  final String? source;

  bool get usableForActions =>
      complete &&
      !stale &&
      snapshotExpiresAt != null &&
      snapshotExpiresAt!.isAfter(DateTime.now().toUtc());

  factory DataMeta.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Missing data metadata.');
    final json = connectionJsonMap(value);
    final fetchedAt = _requiredTimestamp(json['fetchedAt']);
    final asOf = _requiredTimestamp(json['asOf']);
    final snapshotExpiresAt = _requiredTimestamp(json['snapshotExpiresAt']);
    final stale = json['stale'];
    final complete = json['complete'];
    if (stale is! bool ||
        complete is! bool ||
        asOf.isAfter(fetchedAt) ||
        snapshotExpiresAt.isBefore(asOf) ||
        (!stale && !snapshotExpiresAt.isAfter(DateTime.now().toUtc()))) {
      throw const FormatException('Unproven data freshness.');
    }
    return DataMeta(
      fetchedAt: fetchedAt,
      asOf: asOf,
      snapshotExpiresAt: snapshotExpiresAt,
      stale: stale,
      complete: complete,
      source: json['source'] is String ? json['source'] as String : null,
    );
  }

  static DateTime _requiredTimestamp(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw const FormatException('Missing data timestamp.');
    }
    final parsed = DateTime.tryParse(value)?.toUtc();
    if (parsed == null) throw const FormatException('Invalid data timestamp.');
    return parsed;
  }
}

@immutable
class NormalizedPage<T> {
  const NormalizedPage({
    required this.rows,
    required this.nextCursor,
    required this.meta,
  });

  final List<T> rows;
  final String? nextCursor;
  final DataMeta meta;
}

@immutable
class NormalizedBalance {
  const NormalizedBalance({
    required this.exchange,
    required this.product,
    required this.environment,
    required this.region,
    required this.asset,
    required this.available,
    required this.locked,
    required this.total,
    required this.unit,
  });

  final String exchange;
  final String product;
  final String environment;
  final String region;
  final String asset;
  final String? available;
  final String? locked;
  final String? total;
  final String unit;

  factory NormalizedBalance.fromJson(Object? value) {
    final json = connectionJsonMap(value);
    return NormalizedBalance(
      exchange: _string(json['exchange']),
      product: _string(json['product']),
      environment: _string(json['environment']),
      region: _string(json['region']),
      asset: _string(json['asset']),
      available: _nullableString(json['available']),
      locked: _nullableString(json['locked']),
      total: _nullableString(json['total']),
      unit: _string(json['unit']),
    );
  }
}

@immutable
class NormalizedPosition {
  const NormalizedPosition({
    required this.exchange,
    required this.product,
    required this.environment,
    required this.region,
    required this.instrument,
    required this.nativeQuantity,
    required this.quantityUnit,
    required this.baseQuantity,
    required this.marginMode,
    required this.marginCurrency,
    required this.positionId,
    required this.nativeAsset,
    required this.contractValue,
    required this.contractValueUnit,
    required this.contractType,
    required this.settlementAsset,
    required this.metadataVersion,
    required this.side,
    required this.positionMode,
    required this.entryPrice,
    required this.markPrice,
    required this.unrealizedPnl,
  });

  final String exchange;
  final String product;
  final String environment;
  final String region;
  final String instrument;
  final String? nativeQuantity;
  final String? quantityUnit;
  final String? baseQuantity;
  final String? marginMode;
  final String? marginCurrency;
  final String? positionId;
  final String? nativeAsset;
  final String? contractValue;
  final String? contractValueUnit;
  final String? contractType;
  final String? settlementAsset;
  final String? metadataVersion;
  final String? side;
  final String? positionMode;
  final String? entryPrice;
  final String? markPrice;
  final String? unrealizedPnl;

  factory NormalizedPosition.fromJson(Object? value) {
    final json = connectionJsonMap(value);
    return NormalizedPosition(
      exchange: _string(json['exchange']),
      product: _string(json['product']),
      environment: _string(json['environment']),
      region: _string(json['region']),
      instrument: _string(json['instrument']),
      nativeQuantity: _nullableString(json['nativeQuantity']),
      quantityUnit: _nullableString(json['quantityUnit']),
      baseQuantity: _nullableString(json['baseQuantity']),
      marginMode: _nullableString(json['marginMode']),
      marginCurrency: _nullableString(json['marginCurrency']),
      positionId: _nullableString(json['positionId']),
      nativeAsset: _nullableString(json['nativeAsset']),
      contractValue: _nullableString(json['contractValue']),
      contractValueUnit: _nullableString(json['contractValueUnit']),
      contractType: _nullableString(json['contractType']),
      settlementAsset: _nullableString(json['settlementAsset']),
      metadataVersion: _nullableString(json['metadataVersion']),
      side: _nullableString(json['side']),
      positionMode: _nullableString(json['positionMode']),
      entryPrice: _nullableString(json['entryPrice']),
      markPrice: _nullableString(json['markPrice']),
      unrealizedPnl: _nullableString(json['unrealizedPnl']),
    );
  }
}

@immutable
class NormalizedOrder {
  const NormalizedOrder({
    required this.exchange,
    required this.product,
    required this.environment,
    required this.region,
    required this.orderId,
    required this.instrument,
    required this.side,
    required this.orderType,
    required this.status,
    required this.nativeQuantity,
    required this.quantityUnit,
    required this.averagePrice,
    required this.limitPrice,
    required this.filledQuantity,
    required this.eventTime,
    required this.nativeAsset,
    required this.filledQuantityUnit,
    required this.clientOrderId,
    required this.metadataVersion,
  });

  final String exchange;
  final String product;
  final String environment;
  final String region;
  final String orderId;
  final String instrument;
  final String? side;
  final String? orderType;
  final String status;
  final String? nativeQuantity;
  final String? quantityUnit;
  final String? averagePrice;
  final String? limitPrice;
  final String? filledQuantity;
  final String? eventTime;
  final String? nativeAsset;
  final String? filledQuantityUnit;
  final String? clientOrderId;
  final String? metadataVersion;

  factory NormalizedOrder.fromJson(Object? value) {
    final json = connectionJsonMap(value);
    return NormalizedOrder(
      exchange: _string(json['exchange']),
      product: _string(json['product']),
      environment: _string(json['environment']),
      region: _string(json['region']),
      orderId: _string(json['orderId']),
      instrument: _string(json['instrument']),
      side: _nullableString(json['side']),
      orderType: _nullableString(json['orderType']),
      status: _string(json['status']),
      nativeQuantity: _nullableString(json['nativeQuantity']),
      quantityUnit: _nullableString(json['quantityUnit']),
      averagePrice: _nullableString(json['averagePrice']),
      limitPrice: _nullableString(json['limitPrice']),
      filledQuantity: _nullableString(json['filledQuantity']),
      eventTime: _nullableString(json['eventTime']),
      nativeAsset: _nullableString(json['nativeAsset']),
      filledQuantityUnit: _nullableString(json['filledQuantityUnit']),
      clientOrderId: _nullableString(json['clientOrderId']),
      metadataVersion: _nullableString(json['metadataVersion']),
    );
  }
}

String? _nullableString(Object? value) => value is String ? value : null;
