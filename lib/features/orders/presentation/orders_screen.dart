// File Name: orders_screen.dart
// File Path: lib/features/orders/presentation/orders_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/widgets/crypto_icon.dart';
import 'providers/order_provider.dart';
import '../data/okx_order_model.dart';
import '../data/okx_position_model.dart';
import 'package:intl/intl.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Thêm import này để lấy trạng thái Dark Mode
import '../../portfolio/presentation/widgets/portfolio_currency_amount.dart';
import '../../settings/presentation/settings_screen.dart'
    show currencyProvider, vndExchangeRateProvider;
import 'widgets/order_filter_controls.dart';
import 'widgets/order_notional.dart';
import 'widgets/responsive_order_grid.dart';

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
    final isDark = ref.watch(
      isDarkModeProvider,
    ); // Lắng nghe trạng thái Dark Mode
    final currency = ref.watch(currencyProvider);
    final exchangeRate = ref.watch(vndExchangeRateProvider).value ?? 25400.0;
    final isBalanceHidden = ref.watch(hideBalanceProvider);

    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Quản lý Giao dịch',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      body: NavigationContentFrame(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: OrderFilterControls(
                currentTab: currentTab,
                currentFilter: currentFilter,
                isDark: isDark,
                onTabChanged: (tab) {
                  ref.read(orderTabProvider.notifier).state = tab;
                },
                onFilterChanged: (filter) {
                  ref.read(orderFilterProvider.notifier).state = filter;
                },
              ),
            ),

            Divider(
              height: 16,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),

            // --- Nội dung chính ---
            Expanded(
              child: _buildBodyContent(
                context,
                currentTab,
                currentFilter,
                isDark,
                currency,
                exchangeRate,
                isBalanceHidden,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent(
    BuildContext context,
    OrderTab currentTab,
    String filter,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
  ) {
    if (currentTab == OrderTab.positions) {
      if (filter == 'SPOT') {
        return Center(
          child: Text(
            'Giao dịch SPOT không hỗ trợ Vị thế mở.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        );
      }

      final positionsAsyncValue = ref.watch(positionsFutureProvider);
      return RefreshIndicator(
        color: isDark ? Colors.black : Colors.black,
        backgroundColor: isDark ? Colors.white : Colors.white,
        onRefresh: () async => ref.invalidate(positionsFutureProvider),
        child: positionsAsyncValue.when(
          skipLoadingOnReload: true,
          loading: () => Center(
            child: CircularProgressIndicator(
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          error: (error, stack) => Center(
            child: Text(
              'Lỗi: $error',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.redAccent : Colors.red,
              ),
            ),
          ),
          data: (positions) {
            if (positions.isEmpty) {
              return _buildEmptyState('Không có vị thế nào đang mở.', isDark);
            }
            return ResponsiveOrderGrid(
              cardExtent: 270,
              children: positions
                  .map(
                    (position) => _buildPositionCard(
                      position,
                      isDark,
                      currency,
                      exchangeRate,
                      isBalanceHidden,
                    ),
                  )
                  .toList(),
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
          loading: () => Center(
            child: CircularProgressIndicator(
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          error: (error, stack) => Center(
            child: Text(
              'Lỗi: $error',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.redAccent : Colors.red,
              ),
            ),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return _buildEmptyState(
                currentTab == OrderTab.pending
                    ? 'Không có lệnh nào đang chờ khớp.'
                    : 'Không có giao dịch nào trong 7 ngày qua.',
                isDark,
              );
            }
            return ResponsiveOrderGrid(
              cardExtent: 190,
              children: orders
                  .map(
                    (order) => _buildOrderCard(
                      order,
                      currentTab,
                      isDark,
                      currency,
                      exchangeRate,
                      isBalanceHidden,
                    ),
                  )
                  .toList(),
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
        Center(
          child: Text(
            message,
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotionalRow({
    required String label,
    required TradeNotional? notional,
    required String currency,
    required double exchangeRate,
    required bool isHidden,
    required Color textColor,
    required Color subtitleColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label:', style: TextStyle(color: subtitleColor, fontSize: 10)),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: notional == null
                ? Text(
                    '--',
                    style: TextStyle(
                      color: subtitleColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  )
                : PortfolioCurrencyAmount(
                    usdtAmount: notional.usdAmount,
                    currencyMode: currency,
                    vndRate: exchangeRate,
                    hidden: isHidden,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    textAlign: TextAlign.right,
                    primaryStyle: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    secondaryStyle: TextStyle(
                      color: subtitleColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 9,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // --- Thẻ hiển thị VỊ THẾ MỞ ---
  Widget _buildPositionCard(
    OkxPosition position,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
  ) {
    final posSide = position.posSide.toUpperCase();
    final isLong = posSide == 'LONG';

    final sideColor = posSide == 'NET'
        ? (isDark ? Colors.white : Colors.black)
        : (isLong ? Colors.green : Colors.redAccent);
    final sideText = posSide == 'NET' ? 'VỊ THẾ' : (isLong ? 'LONG' : 'SHORT');

    final double pnl = double.tryParse(position.upl) ?? 0.0;
    final pnlColor = pnl >= 0 ? Colors.green : Colors.redAccent;
    final pnlSign = pnl >= 0 ? '+' : '';
    final String pnlFormatted = NumberFormat(
      "#,##0.00",
      "en_US",
    ).format(pnl.abs());

    final double pnlRatio = double.tryParse(position.uplRatio) ?? 0.0;
    final String pnlRatioPercent =
        '$pnlSign${(pnlRatio * 100).toStringAsFixed(2)}%';

    final String baseCoin = position.instId.split('-').isNotEmpty
        ? position.instId.split('-').first
        : '?';

    // Bảng màu cho Card
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade500;
    final iconBgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;

    return Card(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
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
                      CryptoIcon(
                        symbol: baseCoin,
                        size: 20,
                        backgroundColor: iconBgColor,
                        textColor: textColor,
                        textSize: 10,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          position.instId,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: sideColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sideText,
                        style: TextStyle(
                          color: sideColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${position.lever}x',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Divider(
              height: 16,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            ),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lãi / Lỗ chưa thực hiện:',
                    style: TextStyle(color: subtitleColor, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$pnlSign$pnlFormatted ',
                      style: TextStyle(
                        color: pnlColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      pnlRatioPercent,
                      style: TextStyle(
                        color: pnlColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            _buildNotionalRow(
              label: 'Giá trị vị thế',
              notional: resolvePositionNotional(position),
              currency: currency,
              exchangeRate: exchangeRate,
              isHidden: isBalanceHidden,
              textColor: textColor,
              subtitleColor: subtitleColor,
            ),
            Divider(
              height: 16,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Giá vào',
                        style: TextStyle(color: subtitleColor, fontSize: 9),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatNumber(position.avgPx),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Giá mark',
                        style: TextStyle(color: subtitleColor, fontSize: 9),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatNumber(position.markPx),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Thanh lý',
                        style: TextStyle(color: Colors.redAccent, fontSize: 9),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        position.liqPx.isEmpty
                            ? '--'
                            : _formatNumber(position.liqPx),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: textColor,
                        ),
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
  Widget _buildOrderCard(
    OkxOrder order,
    OrderTab currentTab,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
  ) {
    final isBuy = order.side.toLowerCase() == 'buy';
    final sideColor = isBuy ? Colors.green : Colors.redAccent;
    final sideText = isBuy ? 'MUA' : 'BÁN';

    final int? timestampMs = int.tryParse(order.cTime);
    String timeString = '--';
    if (timestampMs != null) {
      final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      timeString = DateFormat('dd/MM/yyyy HH:mm').format(date);
    }

    final String baseCoin = order.instId.split('-').isNotEmpty
        ? order.instId.split('-').first
        : '?';

    // Bảng màu
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade500;
    final iconBgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;
    final notional = resolveOrderNotional(order);

    return Card(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
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
                      CryptoIcon(
                        symbol: baseCoin,
                        size: 20,
                        backgroundColor: iconBgColor,
                        textColor: textColor,
                        textSize: 10,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          order.instId,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (order.lever.isNotEmpty && order.lever != '0') ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${order.lever}x',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                    Text(
                      sideText,
                      style: TextStyle(
                        color: sideColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeString,
                      style: TextStyle(color: subtitleColor, fontSize: 9),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Giá: ${_formatNumber(order.px)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'KL: ${_formatNumber(order.sz)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildNotionalRow(
              label: notional?.source == TradeNotionalSource.filledOrder
                  ? 'Giá trị đã khớp'
                  : 'Giá trị lệnh',
              notional: notional,
              currency: currency,
              exchangeRate: exchangeRate,
              isHidden: isBalanceHidden,
              textColor: textColor,
              subtitleColor: subtitleColor,
            ),
          ],
        ),
      ),
    );
  }
}
