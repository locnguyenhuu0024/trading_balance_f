import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/order_provider.dart';

class OrderFilterControls extends StatelessWidget {
  const OrderFilterControls({
    super.key,
    required this.currentTab,
    required this.currentFilter,
    required this.isDark,
    required this.onTabChanged,
    required this.onFilterChanged,
    this.binanceProducts,
  });

  final List<String>? binanceProducts;
  final OrderTab currentTab;
  final String currentFilter;
  final bool isDark;
  final ValueChanged<OrderTab> onTabChanged;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final textColor = AppPalette.forBrightness(isDark).ink;
    const tabs = <(OrderTab, String)>[
      (OrderTab.positions, 'Vị thế'),
      (OrderTab.pending, 'Chờ khớp'),
      (OrderTab.history, 'Lịch sử'),
    ];
    final options = binanceProducts == null
        ? <(String, String)>[
            ('ALL', 'Tất cả'),
            ('SPOT', 'Spot'),
            ('MARGIN', 'Margin'),
            ('SWAP', 'Perpetual'),
            ('FUTURES', 'Futures'),
          ]
        : <(String, String)>[
            ('ALL', 'Tất cả'),
            if (binanceProducts!.contains('SWAP')) ('SWAP', 'USDⓈ-M'),
            if (binanceProducts!.contains('SPOT')) ('SPOT', 'Spot'),
            if (binanceProducts!.contains('MARGIN')) ('MARGIN', 'Margin'),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          key: const Key('order-tab-select'),
          scrollDirection: Axis.horizontal,
          child: Row(
            key: const Key('order-tab-select-face'),
            children: [
              const SizedBox(key: Key('order-tab-select-icon')),
              for (final option in tabs)
                Semantics(
                  button: true,
                  selected: currentTab == option.$1,
                  child: TextButton(
                    onPressed: () => onTabChanged(option.$1),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: textColor,
                    ),
                    child: Text(
                      option.$2,
                      style: TextStyle(
                        fontWeight: currentTab == option.$1
                            ? FontWeight.bold
                            : FontWeight.normal,
                        decoration: currentTab == option.$1
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          key: const Key('order-type-select'),
          scrollDirection: Axis.horizontal,
          child: Row(
            key: const Key('order-type-select-face'),
            children: [
              const SizedBox(key: Key('order-type-select-icon')),
              for (final option in options)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),
                    child: ChoiceChip(
                      label: Text(option.$2),
                      selected: currentFilter == option.$1,
                      onSelected: (_) => onFilterChanged(option.$1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
