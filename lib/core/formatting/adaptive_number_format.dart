import 'package:intl/intl.dart';

String formatAdaptiveNumber(String value) {
  if (value.isEmpty) return '--';
  final numValue = double.tryParse(value);
  if (numValue == null) return value;

  if (numValue == 0) {
    return "0.00";
  } else if (numValue >= 1000) {
    return NumberFormat("#,##0.00", "en_US").format(numValue);
  } else if (numValue >= 1) {
    return NumberFormat("#,##0.00##", "en_US").format(numValue);
  } else {
    return NumberFormat("0.00######", "en_US").format(numValue);
  }
}
