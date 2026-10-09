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

  static const _filters = ['ALL', 'SPOT', 'MARGIN', 'SWAP', 'FUTURES'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.forBrightness(isDark);
    final surfaceColor = palette.raised;
    final textColor = palette.ink;
    final borderColor = palette.border;

    final tabSelect = DropdownButtonFormField<OrderTab>(
      key: const Key('order-tab-select'),
      initialValue: currentTab,
      isExpanded: true,
      dropdownColor: surfaceColor,
      decoration: _decoration(
        'Trạng thái',
        surfaceColor,
        borderColor,
        textColor,
      ),
      icon: Icon(Icons.unfold_more_rounded, color: textColor),
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      items: const [
        DropdownMenuItem(value: OrderTab.positions, child: Text('Vị thế')),
        DropdownMenuItem(value: OrderTab.pending, child: Text('Đang chờ')),
        DropdownMenuItem(value: OrderTab.history, child: Text('Lịch sử')),
      ],
      onChanged: (value) {
        if (value != null) onTabChanged(value);
      },
    );

    final filterSelect = DropdownButtonFormField<String>(
      key: const Key('order-type-select'),
      initialValue: currentFilter,
      isExpanded: true,
      dropdownColor: surfaceColor,
      decoration: _decoration(
        'Loại giao dịch',
        surfaceColor,
        borderColor,
        textColor,
      ),
      icon: Icon(Icons.unfold_more_rounded, color: textColor),
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      items: _filters
          .map((filter) => DropdownMenuItem(value: filter, child: Text(filter)))
          .toList(),
      onChanged: (value) {
        if (value != null) onFilterChanged(value);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tabSelect,
              const SizedBox(height: AppTokens.space3),
              filterSelect,
            ],
          );
        }

        if (constraints.maxWidth < 600) {
          return Row(
            children: [
              Expanded(child: tabSelect),
              const SizedBox(width: AppTokens.space2),
              Expanded(child: filterSelect),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: tabSelect),
            const SizedBox(width: AppTokens.space3),
            Expanded(child: filterSelect),
          ],
        );
      },
    );
  }

  InputDecoration _decoration(
    String label,
    Color surfaceColor,
    Color borderColor,
    Color textColor,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: textColor),
      filled: true,
      fillColor: surfaceColor,
      isDense: true,
      constraints: const BoxConstraints(
        minHeight: AppTokens.minimumTouchTarget,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space3,
        vertical: AppTokens.space3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        borderSide: BorderSide(color: borderColor),
      ),
    );
  }
}
