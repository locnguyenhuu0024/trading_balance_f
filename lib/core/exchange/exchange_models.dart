enum ExchangeSource { okx, binance }

enum ExchangeProduct { spot, margin, swap, futures }

enum ExchangeOrderKind { ordinary, conditional }

enum ExchangePositionSide { net, long, short, unknown }

/// Exact decimal text used by exchange records. The original scale and sign
/// are preserved; exponent notation and non-finite values are rejected.
class ExchangeAmount {
  ExchangeAmount._(this.text);

  static final RegExp _decimalPattern = RegExp(
    r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$',
  );

  final String text;

  static ExchangeAmount? tryParse(Object? value) {
    if (value is! String && value is! num) return null;
    if (value is num && !value.isFinite) return null;
    final text = value.toString().trim();
    if (!_decimalPattern.hasMatch(text)) return null;
    return ExchangeAmount._(text);
  }

  bool get isZero {
    final unsigned = text.startsWith('-') || text.startsWith('+')
        ? text.substring(1)
        : text;
    return unsigned
        .replaceAll('.', '')
        .split('')
        .every((digit) => digit == '0');
  }

  bool get isPositive {
    if (text.startsWith('-') || isZero) return false;
    return true;
  }

  double? get finiteDouble {
    final result = double.tryParse(text);
    return result != null && result.isFinite ? result : null;
  }

  static ExchangeAmount add(ExchangeAmount left, ExchangeAmount right) =>
      ExchangeAmount._(_addDecimalText(left.text, right.text));

  static ExchangeAmount multiply(ExchangeAmount left, ExchangeAmount right) =>
      ExchangeAmount._(_multiplyDecimalText(left.text, right.text));

  @override
  String toString() => text;
}

class ExchangeValue<T> {
  const ExchangeValue.available(this.value) : reason = null;
  const ExchangeValue.unavailable(this.reason) : value = null;

  final T? value;
  final String? reason;

  bool get isAvailable => value != null;
}

class ExchangeMoney {
  const ExchangeMoney({required this.amount, required this.currency});

  static final RegExp _currencyPattern = RegExp(r'^[A-Za-z0-9]{1,20}$');

  final ExchangeAmount amount;
  final String currency;

  static ExchangeMoney? tryParse(Object? amount, Object? currency) {
    if (currency is! String) return null;
    final code = currency.trim();
    if (!_currencyPattern.hasMatch(code)) return null;
    final value = ExchangeAmount.tryParse(amount);
    if (value == null) return null;
    return ExchangeMoney(amount: value, currency: code.toUpperCase());
  }

  ExchangeMoney add(ExchangeMoney other) {
    if (currency != other.currency) {
      throw ArgumentError('Exchange money currencies must match.');
    }
    return ExchangeMoney(
      amount: ExchangeAmount.add(amount, other.amount),
      currency: currency,
    );
  }

  ExchangeMoney multiply(ExchangeAmount multiplier) => ExchangeMoney(
    amount: ExchangeAmount.multiply(amount, multiplier),
    currency: currency,
  );

  ExchangeMoney convertTo({
    required String targetCurrency,
    required ExchangeAmount rate,
  }) {
    final converted = ExchangeMoney.tryParse(amount.text, targetCurrency);
    if (converted == null || !rate.isPositive || rate.finiteDouble == null) {
      throw ArgumentError('A finite positive conversion rate is required.');
    }
    return ExchangeMoney(
      amount: ExchangeAmount.multiply(amount, rate),
      currency: converted.currency,
    );
  }

  @override
  String toString() => '${amount.text} $currency';
}

class ExchangeReadIssue {
  const ExchangeReadIssue({
    required this.code,
    required this.message,
    this.instrument,
  });

  final String code;
  final String message;
  final String? instrument;
}

class ExchangeInstrument {
  const ExchangeInstrument({
    required this.source,
    required this.product,
    required this.symbol,
    required this.baseAsset,
    required this.quoteAsset,
    required this.settlementAsset,
    this.status,
    this.contractType,
    this.nativeRecord,
  });

  final ExchangeSource source;
  final ExchangeProduct? product;
  final String symbol;
  final ExchangeValue<String> baseAsset;
  final ExchangeValue<String> quoteAsset;
  final ExchangeValue<String> settlementAsset;
  final String? status;
  final String? contractType;
  final Object? nativeRecord;

  String get identityKey =>
      '${source.name}|${product?.name ?? 'unknown'}|$symbol';
}

class ExchangeCatalog {
  ExchangeCatalog({
    required Iterable<ExchangeInstrument> instruments,
    Iterable<ExchangeReadIssue> issues = const <ExchangeReadIssue>[],
    required this.source,
    required this.product,
    required this.generation,
  }) : instruments = List<ExchangeInstrument>.unmodifiable(instruments),
       issues = List<ExchangeReadIssue>.unmodifiable(issues);

  final ExchangeSource source;
  final ExchangeProduct product;
  final int generation;
  final List<ExchangeInstrument> instruments;
  final List<ExchangeReadIssue> issues;

  bool get catalogComplete => issues.isEmpty;
}

class ExchangeBalance {
  const ExchangeBalance({
    required this.source,
    required this.product,
    required this.wallet,
    required this.asset,
    required this.free,
    required this.locked,
    this.reportedTotal,
    this.reportedUsdValue,
    this.nativeRecord,
  });

  final ExchangeSource source;
  final ExchangeProduct? product;
  final String wallet;
  final String asset;
  final ExchangeValue<ExchangeAmount> free;
  final ExchangeValue<ExchangeAmount> locked;
  final ExchangeValue<ExchangeAmount>? reportedTotal;
  final ExchangeValue<ExchangeMoney>? reportedUsdValue;
  final Object? nativeRecord;

  ExchangeValue<ExchangeAmount> get availableTotal {
    final freeAmount = free.value;
    final lockedAmount = locked.value;
    if (freeAmount == null || lockedAmount == null) {
      return const ExchangeValue.unavailable(
        'Free or locked balance is unavailable.',
      );
    }
    return ExchangeValue.available(
      ExchangeAmount.add(freeAmount, lockedAmount),
    );
  }
}

class ExchangeAccountSnapshot {
  ExchangeAccountSnapshot({
    required this.source,
    required this.product,
    required this.generation,
    required Iterable<ExchangeBalance> balances,
    required this.reportedEquity,
    required this.unrealizedPnl,
    required this.equityIncludesUnrealizedPnl,
    this.accountMode,
    Iterable<ExchangePosition> positions = const <ExchangePosition>[],
    Iterable<ExchangeReadIssue> issues = const <ExchangeReadIssue>[],
    this.nativeRecord,
  }) : balances = List<ExchangeBalance>.unmodifiable(balances),
       positions = List<ExchangePosition>.unmodifiable(positions),
       issues = List<ExchangeReadIssue>.unmodifiable(issues);

  final ExchangeSource source;
  final ExchangeProduct? product;
  final int generation;
  final String? accountMode;
  final List<ExchangeBalance> balances;
  final ExchangeValue<ExchangeMoney> reportedEquity;
  final ExchangeValue<ExchangeMoney> unrealizedPnl;
  final bool equityIncludesUnrealizedPnl;
  final List<ExchangePosition> positions;
  final List<ExchangeReadIssue> issues;
  final Object? nativeRecord;

  bool get hasPartialData => issues.isNotEmpty;
}

class ExchangeOrder {
  const ExchangeOrder({
    required this.source,
    required this.product,
    required this.kind,
    required this.symbol,
    required this.nativeId,
    required this.side,
    required this.status,
    required this.quantity,
    required this.executedQuantity,
    required this.quoteAmount,
    required this.createdAtMilliseconds,
    this.updatedAtMilliseconds,
    this.price,
    this.actualOrderId,
    this.conditionalParentId,
    this.conditionalParent,
    this.countsTowardExecution = true,
    this.nativeRecord,
    this.okxActionDto,
  });

  final ExchangeSource source;
  final ExchangeProduct? product;
  final ExchangeOrderKind kind;
  final String symbol;
  final String nativeId;
  final String side;
  final String status;
  final ExchangeValue<ExchangeAmount> quantity;
  final ExchangeValue<ExchangeAmount> executedQuantity;
  final ExchangeValue<ExchangeMoney> quoteAmount;
  final int? createdAtMilliseconds;
  final int? updatedAtMilliseconds;
  final ExchangeValue<ExchangeMoney>? price;
  final String? actualOrderId;
  final String? conditionalParentId;
  final ExchangeOrder? conditionalParent;
  final bool countsTowardExecution;
  final Object? nativeRecord;

  /// Only the OKX adapter sets this field. Binance records never carry an
  /// actionable OKX DTO even when a numeric order ID happens to match.
  final Object? okxActionDto;

  String get identityKey => <String>[
    source.name,
    product?.name ?? 'unknown',
    kind.name,
    symbol,
    nativeId,
  ].join('|');
}

class ExchangePosition {
  const ExchangePosition({
    required this.source,
    required this.product,
    required this.symbol,
    required this.side,
    required this.positionAmount,
    required this.entryPrice,
    required this.markPrice,
    required this.unrealizedPnl,
    required this.marginMode,
    required this.leverage,
    required this.marginCurrency,
    this.nativeId,
    this.nativeRecord,
  });

  final ExchangeSource source;
  final ExchangeProduct? product;
  final String symbol;
  final ExchangePositionSide side;
  final ExchangeValue<ExchangeAmount> positionAmount;
  final ExchangeValue<ExchangeAmount> entryPrice;
  final ExchangeValue<ExchangeAmount> markPrice;
  final ExchangeValue<ExchangeMoney> unrealizedPnl;
  final ExchangeValue<String> marginMode;
  final ExchangeValue<ExchangeAmount> leverage;
  final ExchangeValue<String> marginCurrency;
  final String? nativeId;
  final Object? nativeRecord;

  ExchangePositionSide? get effectiveDirection {
    if (side == ExchangePositionSide.unknown) return null;
    if (side != ExchangePositionSide.net) return side;
    final amount = positionAmount.value;
    if (amount == null || amount.isZero) return null;
    return amount.isPositive
        ? ExchangePositionSide.long
        : ExchangePositionSide.short;
  }

  String get identityKey => <String>[
    source.name,
    product?.name ?? 'unknown',
    symbol,
    side.name,
    nativeId ?? '',
  ].join('|');
}

class ExchangeQuoteKey {
  const ExchangeQuoteKey({
    required this.source,
    required this.product,
    required this.instrument,
  });

  final ExchangeSource source;
  final ExchangeProduct? product;
  final String instrument;

  String get value =>
      '${source.name}|${product?.name ?? 'unknown'}|$instrument';

  @override
  bool operator ==(Object other) =>
      other is ExchangeQuoteKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class ExchangeQuote {
  const ExchangeQuote({
    required this.key,
    required this.price,
    required this.quoteCurrency,
    required this.observedAt,
  });

  final ExchangeQuoteKey key;
  final ExchangeAmount price;
  final String quoteCurrency;
  final DateTime observedAt;

  bool get isPositiveFinite =>
      price.isPositive && (price.finiteDouble?.isFinite ?? false);
}

class ExchangeQuoteSnapshot {
  ExchangeQuoteSnapshot({
    required Map<ExchangeQuoteKey, ExchangeValue<ExchangeQuote>> values,
    required this.observedAt,
  }) : values =
           Map<ExchangeQuoteKey, ExchangeValue<ExchangeQuote>>.unmodifiable(
             values,
           );

  final Map<ExchangeQuoteKey, ExchangeValue<ExchangeQuote>> values;
  final DateTime observedAt;
}

String _addDecimalText(String left, String right) {
  final a = _decimalParts(left);
  final b = _decimalParts(right);
  final scale = a.scale > b.scale ? a.scale : b.scale;
  final leftValue = a.coefficient * BigInt.from(10).pow(scale - a.scale);
  final rightValue = b.coefficient * BigInt.from(10).pow(scale - b.scale);
  return _formatDecimal(leftValue + rightValue, scale);
}

String _multiplyDecimalText(String left, String right) {
  final a = _decimalParts(left);
  final b = _decimalParts(right);
  return _formatDecimal(a.coefficient * b.coefficient, a.scale + b.scale);
}

_DecimalParts _decimalParts(String text) {
  final negative = text.startsWith('-');
  final unsigned = text.startsWith('-') || text.startsWith('+')
      ? text.substring(1)
      : text;
  final parts = unsigned.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  final integer = parts[0].isEmpty ? '0' : parts[0];
  var coefficient = BigInt.parse('$integer$fraction');
  if (negative) coefficient = -coefficient;
  return _DecimalParts(coefficient, fraction.length);
}

String _formatDecimal(BigInt coefficient, int scale) {
  if (coefficient == BigInt.zero) return '0';
  final negative = coefficient.isNegative;
  var digits = coefficient.abs().toString();
  if (scale > 0) {
    digits = digits.padLeft(scale + 1, '0');
    final split = digits.length - scale;
    digits = '${digits.substring(0, split)}.${digits.substring(split)}';
    digits = digits
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return negative ? '-$digits' : digits;
}

class _DecimalParts {
  const _DecimalParts(this.coefficient, this.scale);

  final BigInt coefficient;
  final int scale;
}
