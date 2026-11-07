/// Stable exchange identity; display labels are never identifiers.
enum ExchangeId { okx, binance }

class ConnectionProfile {
  const ConnectionProfile({
    required this.connectionId,
    required this.exchange,
    required this.label,
    this.products = const [],
  });
  final String connectionId;
  final ExchangeId exchange;
  final String label;
  final List<String> products;
}

class ExchangeScope {
  const ExchangeScope({
    required this.connectionId,
    required this.exchange,
    required this.credentialGeneration,
    required this.switchEpoch,
  });
  final String connectionId;
  final ExchangeId exchange;
  final int credentialGeneration;
  final int switchEpoch;
  @override
  bool operator ==(Object other) =>
      other is ExchangeScope &&
      other.connectionId == connectionId &&
      other.exchange == exchange &&
      other.credentialGeneration == credentialGeneration &&
      other.switchEpoch == switchEpoch;
  @override
  int get hashCode =>
      Object.hash(connectionId, exchange, credentialGeneration, switchEpoch);
}

class ExchangeCapabilities {
  const ExchangeCapabilities({
    this.readableProducts = const [],
    this.unavailableProducts = const [],
  });
  final List<String> readableProducts;
  final List<String> unavailableProducts;
}

class InstrumentKey {
  const InstrumentKey({
    required this.exchange,
    required this.product,
    required this.nativeId,
    this.base,
    this.quote,
  });
  final ExchangeId exchange;
  final String product, nativeId;
  final String? base, quote;
  @override
  bool operator ==(Object other) =>
      other is InstrumentKey &&
      other.exchange == exchange &&
      other.product == product &&
      other.nativeId == nativeId;
  @override
  int get hashCode => Object.hash(exchange, product, nativeId);
}

class AccountSnapshot {
  const AccountSnapshot({
    this.total,
    this.totalCurrency,
    this.isPartial = false,
    this.balances = const [],
    this.walletResults = const [],
    this.marginRows = const [],
    this.issues = const [],
  });
  final String? total, totalCurrency;
  final bool isPartial;
  final List<AssetBalance> balances;
  final List<WalletResult> walletResults;
  final List<MarginAccountRow> marginRows;
  final List<String> issues;
}

class WalletResult {
  const WalletResult({required this.wallet, this.available = true});
  final String wallet;
  final bool available;
}

class AssetBalance {
  const AssetBalance({
    required this.wallet,
    required this.asset,
    this.total,
    this.available,
    this.frozen,
    this.borrowed,
    this.interest,
    this.net,
    this.unrealizedPnl,
    this.valueUsdt,
  });
  final String wallet, asset;
  final String? total,
      available,
      frozen,
      borrowed,
      interest,
      net,
      unrealizedPnl,
      valueUsdt;
}

class ExchangePosition {
  const ExchangePosition({
    required this.key,
    required this.productLabel,
    this.side,
    this.direction,
    this.size,
    this.entry,
    this.mark,
    this.liquidation,
    this.leverage,
    this.marginMode,
    this.unrealizedPnl,
    this.unrealizedPnlRatio,
    this.notional,
    this.positionId,
    this.positionCurrency,
    this.marginCurrency,
    this.native,
  });
  final InstrumentKey key;
  final String productLabel;
  final String? side,
      direction,
      size,
      entry,
      mark,
      liquidation,
      leverage,
      marginMode,
      unrealizedPnl,
      unrealizedPnlRatio,
      notional,
      positionId,
      positionCurrency,
      marginCurrency;
  final Object? native;
}

class ExchangeOrder {
  const ExchangeOrder({
    required this.id,
    required this.key,
    required this.productLabel,
    this.type,
    this.side,
    this.price,
    this.quantity,
    this.filled,
    this.average,
    this.notional,
    this.filledNotional,
    this.leverage,
    this.state,
    this.createdAtMs,
    this.native,
  });
  final String id;
  final InstrumentKey key;
  final String productLabel;
  final String? type,
      side,
      price,
      quantity,
      filled,
      average,
      notional,
      filledNotional,
      leverage,
      state,
      createdAtMs;
  final Object? native;
}

class MarginAccountRow {
  const MarginAccountRow({
    this.asset,
    this.key,
    this.borrowed,
    this.interest,
    this.net,
    this.marginLevel,
    this.liquidation,
    this.indexPrice,
    this.marginRatio,
    this.baseNet,
    this.baseBorrowed,
    this.baseInterest,
    this.quoteNet,
    this.quoteBorrowed,
    this.quoteInterest,
  });
  final String? marginRatio,
      baseNet,
      baseBorrowed,
      baseInterest,
      quoteNet,
      quoteBorrowed,
      quoteInterest;
  final String? asset,
      borrowed,
      interest,
      net,
      marginLevel,
      liquidation,
      indexPrice;
  final InstrumentKey? key;
}

class Ticker {
  const Ticker({required this.key, this.last, this.change24h});
  final InstrumentKey key;
  final String? last, change24h;
}

class Candle {
  const Candle({
    required this.key,
    this.openTime,
    this.open,
    this.high,
    this.low,
    this.close,
    this.volume,
  });
  final InstrumentKey key;
  final String? openTime, open, high, low, close, volume;
}

enum ExchangeFailureKind {
  transient,
  credential,
  permission,
  unavailableOnPlatform,
  other,
  cancellation,
}

class ExchangeFailure {
  const ExchangeFailure(this.kind, {this.retryAfter});
  final ExchangeFailureKind kind;
  final Duration? retryAfter;
}
