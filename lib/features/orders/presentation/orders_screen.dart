// File Name: orders_screen.dart
// File Path: lib/features/orders/presentation/orders_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/order_provider.dart';
import '../data/okx_order_model.dart';
import '../data/okx_position_model.dart';
import 'package:intl/intl.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Thêm import này để lấy trạng thái Dark Mode

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentTab = ref.read(orderTabProvider);

      if (currentTab == OrderTab.positions) {
        ref.invalidate(positionsFutureProvider);
      } else {
        ref.invalidate(ordersFutureProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatNumber(String value) {
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

  @override
  Widget build(BuildContext context) {
    final currentFilter = ref.watch(orderFilterProvider);
    final currentTab = ref.watch(orderTabProvider);
    final isDark = ref.watch(isDarkModeProvider); // Lắng nghe trạng thái Dark Mode

    final filters = ['SPOT', 'MARGIN', 'SWAP', 'FUTURES'];

    // Khởi tạo màu nền chung
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text('Quản lý Giao dịch', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: Column(
        children: [
          // --- Tab Chuyển đổi ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: SegmentedButton<OrderTab>(
              segments: const [
                ButtonSegment(value: OrderTab.positions, label: Text('Vị thế')),
                ButtonSegment(value: OrderTab.pending, label: Text('Đang chờ')),
                ButtonSegment(value: OrderTab.history, label: Text('Lịch sử')),
              ],
              selected: {currentTab},
              onSelectionChanged: (Set<OrderTab> newSelection) {
                ref.read(orderTabProvider.notifier).state = newSelection.first;
              },
              style: SegmentedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                selectedForegroundColor: isDark ? Colors.black : Colors.white,
                selectedBackgroundColor: isDark ? Colors.white : Colors.black,
                backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                foregroundColor: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),

          // --- Bộ Lọc Loại Giao Dịch ---
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              itemBuilder: (context, index) {
                final type = filters[index];
                final isSelected = currentFilter == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: isSelected,
                    selectedColor: isDark ? Colors.white : Colors.black,
                    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide.none,
                    onSelected: (selected) {
                      if (selected) ref.read(orderFilterProvider.notifier).state = type;
                    },
                  ),
                );
              },
            ),
          ),

          Divider(height: 16, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),

          // --- Nội dung chính ---
          Expanded(
            child: _buildBodyContent(context, currentTab, currentFilter, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent(BuildContext context, OrderTab currentTab, String filter, bool isDark) {
    if (currentTab == OrderTab.positions) {
      if (filter == 'SPOT') {
        return Center(child: Text('Giao dịch SPOT không hỗ trợ Vị thế mở.', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)));
      }

      final positionsAsyncValue = ref.watch(positionsFutureProvider);
      return RefreshIndicator(
        color: isDark ? Colors.black : Colors.black,
        backgroundColor: isDark ? Colors.white : Colors.white,
        onRefresh: () async => ref.invalidate(positionsFutureProvider),
        child: positionsAsyncValue.when(
          skipLoadingOnReload: true,
          loading: () => Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black)),
          error: (error, stack) => Center(child: Text('Lỗi: $error', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: isDark ? Colors.redAccent : Colors.red))),
          data: (positions) {
            if (positions.isEmpty) return _buildEmptyState('Không có vị thế nào đang mở.', isDark);
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: positions.length,
              itemBuilder: (context, index) => _buildPositionCard(positions[index], isDark),
            );
          },
        ),
      );
    } else {
      final ordersAsyncValue = ref.watch(ordersFutureProvider);
      return RefreshIndicator(
        color: isDark ? Colors.black : Colors.black,
        backgroundColor: isDark ? Colors.white : Colors.white,
        onRefresh: () async => ref.invalidate(ordersFutureProvider),
        child: ordersAsyncValue.when(
          skipLoadingOnReload: true,
          loading: () => Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black)),
          error: (error, stack) => Center(child: Text('Lỗi: $error', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: isDark ? Colors.redAccent : Colors.red))),
          data: (orders) {
            if (orders.isEmpty) {
              return _buildEmptyState(
                  currentTab == OrderTab.pending
                      ? 'Không có lệnh nào đang chờ khớp.'
                      : 'Không có giao dịch nào trong 7 ngày qua.',
                  isDark
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              itemBuilder: (context, index) => _buildOrderCard(orders[index], currentTab, isDark),
            );
          },
        ),
      );
    }
  }

  Widget _buildEmptyState(String message, bool isDark) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(child: Text(message, style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade500, fontSize: 12))),
      ],
    );
  }

  // --- Thẻ hiển thị VỊ THẾ MỞ ---
  Widget _buildPositionCard(OkxPosition position, bool isDark) {
    final posSide = position.posSide.toUpperCase();
    final isLong = posSide == 'LONG';

    final sideColor = posSide == 'NET' ? (isDark ? Colors.white : Colors.black) : (isLong ? Colors.green : Colors.redAccent);
    final sideText = posSide == 'NET' ? 'VỊ THẾ' : (isLong ? 'LONG' : 'SHORT');

    final double pnl = double.tryParse(position.upl) ?? 0.0;
    final pnlColor = pnl >= 0 ? Colors.green : Colors.redAccent;
    final pnlSign = pnl >= 0 ? '+' : '';
    final String pnlFormatted = NumberFormat("#,##0.00", "en_US").format(pnl.abs());

    final double pnlRatio = double.tryParse(position.uplRatio) ?? 0.0;
    final String pnlRatioPercent = '$pnlSign${(pnlRatio * 100).toStringAsFixed(2)}%';

    final String baseCoin = position.instId.split('-').isNotEmpty ? position.instId.split('-').first : '?';

    // Bảng màu cho Card
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade500;
    final iconBgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;

    return Card(
      elevation: 0,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          'https://raw.githubusercontent.com/spothq/cryptocurrency-icons/master/128/color/${baseCoin.toLowerCase()}.png',
                          width: 20,
                          height: 20,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              baseCoin.isNotEmpty ? baseCoin.substring(0, 1).toUpperCase() : '?',
                              style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 10),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          position.instId,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: sideColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sideText,
                        style: TextStyle(color: sideColor, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${position.lever}x',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Divider(height: 16, color: isDark ? Colors.grey.shade800 : Colors.grey.shade100),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Lãi / Lỗ chưa thực hiện:', style: TextStyle(color: subtitleColor, fontSize: 11)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$pnlSign$pnlFormatted ',
                      style: TextStyle(color: pnlColor, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      pnlRatioPercent,
                      style: TextStyle(color: pnlColor, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Giá vào', style: TextStyle(color: subtitleColor, fontSize: 9)),
                      const SizedBox(height: 2),
                      Text(_formatNumber(position.avgPx), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: textColor)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Giá mark', style: TextStyle(color: subtitleColor, fontSize: 9)),
                      const SizedBox(height: 2),
                      Text(_formatNumber(position.markPx), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: textColor)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Thanh lý', style: TextStyle(color: Colors.redAccent, fontSize: 9)),
                      const SizedBox(height: 2),
                      Text(
                          position.liqPx.isEmpty ? '--' : _formatNumber(position.liqPx),
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: textColor)
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Thẻ hiển thị LỆNH ---
  Widget _buildOrderCard(OkxOrder order, OrderTab currentTab, bool isDark) {
    final isBuy = order.side.toLowerCase() == 'buy';
    final sideColor = isBuy ? Colors.green : Colors.redAccent;
    final sideText = isBuy ? 'MUA' : 'BÁN';

    final int? timestampMs = int.tryParse(order.cTime);
    String timeString = '--';
    if (timestampMs != null) {
      final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      timeString = DateFormat('dd/MM/yyyy HH:mm').format(date);
    }

    final String baseCoin = order.instId.split('-').isNotEmpty ? order.instId.split('-').first : '?';

    // Bảng màu
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade500;
    final iconBgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;

    return Card(
      elevation: 0,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          'https://raw.githubusercontent.com/spothq/cryptocurrency-icons/master/128/color/${baseCoin.toLowerCase()}.png',
                          width: 20,
                          height: 20,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              baseCoin.isNotEmpty ? baseCoin.substring(0, 1).toUpperCase() : '?',
                              style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 10),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          order.instId,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (order.lever.isNotEmpty && order.lever != '0') ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${order.lever}x',
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    order.state.toUpperCase(),
                    style: TextStyle(
                      color: currentTab == OrderTab.pending
                          ? (isDark ? Colors.white : Colors.black87)
                          : subtitleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sideText, style: TextStyle(color: sideColor, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(timeString, style: TextStyle(color: subtitleColor, fontSize: 9)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Giá: ${_formatNumber(order.px)}', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 11, color: textColor)),
                    const SizedBox(height: 2),
                    Text('KL: ${_formatNumber(order.sz)}', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 11, color: textColor)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
