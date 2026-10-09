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
  });

  final OrderTab currentTab;
  final String currentFilter;
  final bool isDark;
  final ValueChanged<OrderTab> onTabChanged;
  final ValueChanged<String> onFilterChanged;

  static const _tabs = <(OrderTab, String)>[
    (OrderTab.positions, 'Vị thế'),
    (OrderTab.pending, 'Đang chờ'),
    (OrderTab.history, 'Lịch sử'),
  ];
  static const _filters = ['ALL', 'SPOT', 'MARGIN', 'SWAP', 'FUTURES'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.forBrightness(isDark);
    final surfaceColor = palette.raised;
    final textColor = palette.ink;
    final borderColor = palette.border;
    final focusBorderColor = Theme.of(context).colorScheme.primary;

    final tabLabel = _tabs.firstWhere((option) => option.$1 == currentTab).$2;
    final tabSelect = Semantics(
      label: 'Trạng thái',
      value: tabLabel,
      child: Tooltip(
        message: 'Trạng thái',
        child: Stack(
          children: [
            Positioned.fill(
              top: 4,
              bottom: 4,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('order-tab-select-face'),
                  decoration: _faceDecoration(surfaceColor, borderColor),
                ),
              ),
            ),
            DropdownButtonFormField<OrderTab>(
              key: const Key('order-tab-select'),
              initialValue: currentTab,
              isDense: true,
              isExpanded: true,
              focusColor: Colors.transparent,
              dropdownColor: surfaceColor,
              decoration: _decoration(focusBorderColor),
              icon: Icon(
                Icons.unfold_more_rounded,
                key: const Key('order-tab-select-icon'),
                color: textColor,
                size: 18,
              ),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              items: _tabs
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.$1,
                      child: Text(option.$2),
                    ),
                  )
                  .toList(),
              selectedItemBuilder: (context) => _tabs
                  .map(
                    (option) => Text(
                      option.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      semanticsLabel: option.$2,
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onTabChanged(value);
              },
            ),
          ],
        ),
      ),
    );

    final filterSelect = Semantics(
      label: 'Loại giao dịch',
      value: currentFilter,
      child: Tooltip(
        message: 'Loại giao dịch',
        child: Stack(
          children: [
            Positioned.fill(
              top: 4,
              bottom: 4,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('order-type-select-face'),
                  decoration: _faceDecoration(surfaceColor, borderColor),
                ),
              ),
            ),
            DropdownButtonFormField<String>(
              key: const Key('order-type-select'),
              initialValue: currentFilter,
              isDense: true,
              isExpanded: true,
              focusColor: Colors.transparent,
              dropdownColor: surfaceColor,
              decoration: _decoration(focusBorderColor),
              icon: Icon(
                Icons.unfold_more_rounded,
                key: const Key('order-type-select-icon'),
                color: textColor,
                size: 18,
              ),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              items: _filters
                  .map(
                    (filter) =>
                        DropdownMenuItem(value: filter, child: Text(filter)),
                  )
                  .toList(),
              selectedItemBuilder: (context) => _filters
                  .map(
                    (filter) => Text(
                      filter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      semanticsLabel: filter,
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onFilterChanged(value);
              },
            ),
          ],
        ),
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 286),
      child: Row(
        children: [
          Expanded(child: tabSelect),
          const SizedBox(width: 6),
          Expanded(child: filterSelect),
        ],
      ),
    );
  }

  InputDecoration _decoration(Color focusBorderColor) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.transparent,
      isDense: true,
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        borderSide: BorderSide(color: focusBorderColor, width: 2),
      ),
    );
  }

  BoxDecoration _faceDecoration(Color surfaceColor, Color borderColor) {
    return BoxDecoration(
      color: surfaceColor,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
    );
  }
}
