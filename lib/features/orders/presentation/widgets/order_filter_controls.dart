import 'package:flutter/material.dart';

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

  static const _filters = ['SPOT', 'MARGIN', 'SWAP', 'FUTURES'];

  @override
  Widget build(BuildContext context) {
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

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
      style: TextStyle(
        color: textColor,
        fontSize: 13,
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
      style: TextStyle(
        color: textColor,
        fontSize: 13,
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
        if (constraints.maxWidth < 600) {
          return Column(
            children: [tabSelect, const SizedBox(height: 10), filterSelect],
          );
        }

        return Row(
          children: [
            Expanded(child: tabSelect),
            const SizedBox(width: 12),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
    );
  }
}
