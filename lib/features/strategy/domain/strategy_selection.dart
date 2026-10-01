import 'strategy_models.dart';

class StrategySelectedLevel {
  const StrategySelectedLevel({required this.side, required this.price});

  final StrategySide side;
  final double price;

  String get id => '${side.wireValue}:${price.toStringAsPrecision(14)}';

  Map<String, Object> toJson() => {'side': side.wireValue, 'price': price};
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
    required this.selectedLevels,
    required this.entryBySide,
  });

  final String instrumentId;
  final StrategyInterval interval;
  final List<StrategySelectedLevel> selectedLevels;
  final Map<StrategySide, double> entryBySide;

  factory StrategySelection.validate({
    required String instrumentId,
    required StrategyInterval interval,
    required double referencePrice,
    required List<StrategySelectedLevel> selectedLevels,
    required Map<StrategySide, double> entryBySide,
  }) {
    final normalized = instrumentId.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+-USDT-SWAP$').hasMatch(normalized)) {
      throw const StrategySelectionException(
        'Choose one live USDT linear SWAP instrument.',
      );
    }
    if (!referencePrice.isFinite || referencePrice <= 0) {
      throw const StrategySelectionException(
        'The latest swap price is unavailable.',
      );
    }
    if (selectedLevels.isEmpty || selectedLevels.length > 20) {
      throw const StrategySelectionException(
        'Select between 1 and 20 levels in total.',
      );
    }
    final ids = <String>{};
    for (final level in selectedLevels) {
      if (!level.price.isFinite || level.price <= 0 || !ids.add(level.id)) {
        throw const StrategySelectionException(
          'A selected level is invalid or duplicated.',
        );
      }
      if (level.side == StrategySide.long && level.price >= referencePrice) {
        throw const StrategySelectionException(
          'Long entries must use support below the current price.',
        );
      }
      if (level.side == StrategySide.short && level.price <= referencePrice) {
        throw const StrategySelectionException(
          'Short entries must use resistance above the current price.',
        );
      }
    }

    final selectedSides = selectedLevels.map((level) => level.side).toSet();
    if (selectedSides.length != entryBySide.length ||
        !selectedSides.containsAll(entryBySide.keys)) {
      throw const StrategySelectionException(
        'Choose one entry level for every selected side.',
      );
    }
    for (final side in selectedSides) {
      final sideLevels = selectedLevels
          .where((level) => level.side == side)
          .toList(growable: false);
      final entry = entryBySide[side];
      if (entry == null || !sideLevels.any((level) => level.price == entry)) {
        throw const StrategySelectionException(
          'The entry must be one of the selected levels.',
        );
      }
      final nearestDistance = sideLevels
          .map((level) => (level.price - referencePrice).abs())
          .reduce((a, b) => a < b ? a : b);
      final entryDistance = (entry - referencePrice).abs();
      if (entryDistance > nearestDistance + referencePrice * 1e-12) {
        throw const StrategySelectionException(
          'Choose the selected level nearest the current price as the entry.',
        );
      }
    }

    return StrategySelection._(
      instrumentId: normalized,
      interval: interval,
      selectedLevels: List.unmodifiable(selectedLevels),
      entryBySide: Map.unmodifiable(entryBySide),
    );
  }

  Map<String, Object> toRequestJson({
    required String totalMargin,
    required Map<StrategySide, int> leverage,
    required Map<StrategySide, String> sidePercent,
    required StrategyAllocation allocation,
  }) {
    final body = <String, Object>{
      'instrumentId': instrumentId,
      'interval': interval.bar,
      'selectedLevels': selectedLevels.map((level) => level.toJson()).toList(),
      'entryBySide': {
        for (final entry in entryBySide.entries)
          entry.key.wireValue: entry.value,
      },
      'totalMargin': totalMargin,
      'leverage': {
        for (final side in entryBySide.keys) side.wireValue: leverage[side]!,
      },
      'allocation': allocation.name,
    };
    if (entryBySide.length > 1) {
      body['sidePercent'] = {
        for (final side in entryBySide.keys) side.wireValue: sidePercent[side]!,
      };
    }
    return body;
  }
}
