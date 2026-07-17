class CurrencyDisplayOption {
  const CurrencyDisplayOption({required this.value, required this.label});

  final String value;
  final String label;
}

abstract final class CurrencyDisplayMode {
  static const String usd = 'USD';
  static const String vnd = 'VNĐ';
  static const String usdtVnd = 'USDT_VND';

  static const List<CurrencyDisplayOption> options = [
    CurrencyDisplayOption(value: usd, label: 'USD'),
    CurrencyDisplayOption(value: vnd, label: 'VNĐ'),
    CurrencyDisplayOption(value: usdtVnd, label: 'USDT + VND'),
  ];

  static bool includesVnd(String value) => value == vnd || value == usdtVnd;

  static String labelFor(String value) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return options.first.label;
  }
}
