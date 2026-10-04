import '../../../core/formatting/adaptive_number_format.dart';

/// Formats strategy numbers for display without changing the source values.
class StrategyNumberFormatter {
  const StrategyNumberFormatter._();

  static String amount(Object? value, {String placeholder = '--'}) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return placeholder;
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) return placeholder;

    final magnitude = parsed.abs();
    final formatted = magnitude > 0 && magnitude < 0.00000001
        ? _compactScientific(magnitude)
        : formatAdaptiveNumber(magnitude.toString());
    return parsed.isNegative && magnitude != 0 ? '-$formatted' : formatted;
  }

  static String percent(Object? value, {String placeholder = '--'}) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return placeholder;
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) return placeholder;
    if (parsed.abs() < 0.005) return '0.00';
    return parsed.toStringAsFixed(2);
  }

  static String _compactScientific(double value) {
    final parts = value.toStringAsExponential(7).split('e');
    final significand = parts.first
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    final exponent = int.parse(parts.last);
    return '${significand}e$exponent';
  }
}
