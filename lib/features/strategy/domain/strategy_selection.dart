import 'strategy_models.dart';

enum StrategyDirection {
  long('long'),
  short('short'),
  both('both');

  const StrategyDirection(this.wireValue);

  final String wireValue;

  Set<StrategySide> get sides => switch (this) {
    StrategyDirection.long => {StrategySide.long},
    StrategyDirection.short => {StrategySide.short},
    StrategyDirection.both => {StrategySide.long, StrategySide.short},
  };
}

class StrategySelectedLevel {
  const StrategySelectedLevel({
    required this.side,
    required this.price,
    this.exactPriceText,
    this.levelId,
  });

  final StrategySide side;
  final double price;
  final String? exactPriceText;
  final String? levelId;

  String get priceText {
    final text = exactPriceText ?? price.toString();
    return StrategyDecimal.tryParse(text)?.toString() ?? text;
  }

  String get id {
    final explicitId = levelId;
    if (explicitId != null) return explicitId;
    final canonical =
        StrategyDecimal.tryParse(priceText)?.toString() ?? priceText;
    final encoded = canonical
        .replaceAll('-', 'm')
        .replaceAll('.', '_')
        .replaceAll('+', 'p');
    return '${side.wireValue}_$encoded';
  }

  Map<String, Object> toJson() => {
    'side': side.wireValue,
    'price': priceText,
    'levelId': id,
  };
}

class StrategySelectionException implements Exception {
  const StrategySelectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StrategySelection {
  StrategySelection._({
    required this.instrumentId,
    required this.interval,
    required this.direction,
    required this.selectedLevels,
    required this.entryLevelIdBySide,
  });

  final String instrumentId;
  final StrategyInterval interval;
  final StrategyDirection direction;
  final List<StrategySelectedLevel> selectedLevels;
  final Map<StrategySide, String> entryLevelIdBySide;

  Map<StrategySide, String> get entryBySide => {
    for (final entry in entryLevelIdBySide.entries)
      entry.key: selectedLevels
          .singleWhere((level) => level.id == entry.value)
          .priceText,
  };

  factory StrategySelection.validate({
    required String instrumentId,
    required StrategyInterval interval,
    required double referencePrice,
    String? referencePriceText,
    required StrategyDirection direction,
    required List<StrategySelectedLevel> selectedLevels,
    required Map<StrategySide, String> entryLevelIdBySide,
  }) {
    final normalized = instrumentId.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(normalized)) {
      throw const StrategySelectionException(
        'Choose one live USDT linear SWAP instrument.',
      );
    }
    if (!referencePrice.isFinite || referencePrice <= 0) {
      throw const StrategySelectionException(
        'The reference swap price is unavailable.',
      );
    }
    final reference = StrategyDecimal.tryParse(
      referencePriceText ?? referencePrice.toString(),
    );
    if (reference == null || !reference.isPositive) {
      throw const StrategySelectionException(
        'The reference swap price is invalid.',
      );
    }
    if (selectedLevels.isEmpty ||
        selectedLevels.length > strategyNewSubmissionOrderLimit) {
      throw const StrategySelectionException(
        'Select between 1 and 10 levels in total.',
      );
    }

    final ids = <String>{};
    final levelsById = <String, StrategySelectedLevel>{};
    final decimalsById = <String, StrategyDecimal>{};
    for (final level in selectedLevels) {
      final id = level.id;
      final price = StrategyDecimal.tryParse(level.priceText);
      if (!level.price.isFinite ||
          !level.price.isPositiveDouble ||
          price == null ||
          !price.isPositive ||
          !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
          !ids.add(id)) {
        throw const StrategySelectionException(
          'A selected level ID or exact price is invalid or duplicated.',
        );
      }
      final comparison = price.compareTo(reference);
      if ((level.side == StrategySide.long && comparison >= 0) ||
          (level.side == StrategySide.short && comparison <= 0)) {
        throw const StrategySelectionException(
          'Long entries must use support below the reference price and Short entries must use resistance above it.',
        );
      }
      levelsById[id] = level;
      decimalsById[id] = price;
    }

    final selectedSides = selectedLevels.map((level) => level.side).toSet();
    if (selectedSides.length != direction.sides.length ||
        !selectedSides.containsAll(direction.sides) ||
        direction.sides.length != entryLevelIdBySide.length ||
        !direction.sides.containsAll(entryLevelIdBySide.keys)) {
      throw const StrategySelectionException(
        'Choose a selected order and one entry level for every requested side.',
      );
    }
    for (final side in direction.sides) {
      final entryId = entryLevelIdBySide[side];
      final entry = levelsById[entryId];
      if (entry == null || entry.side != side) {
        throw const StrategySelectionException(
          'Choose one selected entry ID for every side.',
        );
      }
      final sideLevels = selectedLevels
          .where((level) => level.side == side)
          .map((level) => decimalsById[level.id]!)
          .toList(growable: false);
      final nearestDistance = sideLevels
          .map((price) => (price - reference).abs())
          .reduce((left, right) => left.compareTo(right) <= 0 ? left : right);
      final entryDistance = (decimalsById[entryId]! - reference).abs();
      if (entryDistance.compareTo(nearestDistance) > 0) {
        throw const StrategySelectionException(
          'Choose the selected level nearest the reference price as the entry.',
        );
      }
    }

    return StrategySelection._(
      instrumentId: normalized,
      interval: interval,
      direction: direction,
      selectedLevels: List.unmodifiable(selectedLevels),
      entryLevelIdBySide: Map.unmodifiable(entryLevelIdBySide),
    );
  }

  Map<String, Object> toRequestJson({
    required String totalMargin,
    required Map<StrategySide, int> leverage,
    required Map<StrategySide, String> sidePercent,
    required StrategyAllocation allocation,
  }) {
    final entries = entryBySide;
    final body = <String, Object>{
      'instrumentId': instrumentId,
      'interval': interval.bar,
      'direction': direction.wireValue,
      'selectedLevels': selectedLevels.map((level) => level.toJson()).toList(),
      'entryBySide': {
        for (final entry in entries.entries) entry.key.wireValue: entry.value,
      },
      'entryLevelIdBySide': {
        for (final entry in entryLevelIdBySide.entries)
          entry.key.wireValue: entry.value,
      },
      'totalMargin': totalMargin,
      'leverage': {
        for (final side in entryLevelIdBySide.keys)
          side.wireValue: leverage[side]!,
      },
      'allocation': allocation.name,
    };
    if (entryLevelIdBySide.length > 1) {
      body['sidePercent'] = {
        for (final side in entryLevelIdBySide.keys)
          side.wireValue: sidePercent[side]!,
      };
    }
    return body;
  }
}

extension on double {
  bool get isPositiveDouble => isFinite && this > 0;
}
