// File Name: orders_screen.dart
// File Path: lib/features/orders/presentation/orders_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/formatting/adaptive_number_format.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/pnl_color.dart';
import '../../../core/timezone/app_time_zone.dart';
import '../../../core/widgets/crypto_icon.dart';
import 'providers/order_provider.dart';
import 'providers/order_cancellation_flow_provider.dart';
import '../data/okx_order_model.dart';
import '../data/okx_position_model.dart';
import 'providers/position_action_flow_provider.dart';
import 'providers/trade_session_provider.dart';
import 'package:intl/intl.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Thêm import này để lấy trạng thái Dark Mode
import '../../portfolio/presentation/widgets/portfolio_currency_amount.dart';
import '../../settings/presentation/settings_screen.dart'
    show currencyProvider, vndExchangeRateProvider;
import 'widgets/order_filter_controls.dart';
import 'widgets/order_notional.dart';
import 'widgets/order_cancellation_control.dart';
import 'widgets/responsive_order_grid.dart';
import 'widgets/position_action_controls.dart';
import 'widgets/trade_account_controls.dart';

String formatOrderTimestamp(String rawTimestamp, String timeZoneId) {
  final timestampMs = int.tryParse(rawTimestamp);
  if (timestampMs == null) return '--';

  return AppTimeZone.formatEpochMilliseconds(timeZoneId, timestampMs);
}

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
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final currentTab = ref.read(orderTabProvider);
      final currentFilter = ref.read(orderFilterProvider);

      final tradeSession = ref.read(tradeSessionProvider);
      if (tradeSession.session != null && !tradeSession.isAuthenticated) {
        ref.read(tradeSessionProvider.notifier).expire();
        return;
      }
      if (tradeSession.isLoading || !tradeSession.isAuthenticated) return;

      if (currentTab == OrderTab.positions && currentFilter == 'SPOT') return;

      final currentRead = currentTab == OrderTab.positions
          ? (tradeSession.isAuthenticated
                ? ref.read(tradePositionsProvider)
                : ref.read(positionsFutureProvider))
          : ref.read(ordersFutureProvider);
      if (currentRead.isLoading ||
          isTerminalForegroundReadFailure(currentRead.asError?.error)) {
        return;
      }

      if (currentTab == OrderTab.positions) {
        if (tradeSession.isAuthenticated) {
          ref.invalidate(tradePositionsProvider);
        } else {
          ref.invalidate(positionsFutureProvider);
        }
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

  @override
  Widget build(BuildContext context) {
    final currentFilter = ref.watch(orderFilterProvider);
    final currentTab = ref.watch(orderTabProvider);
    final isDark = ref.watch(
      isDarkModeProvider,
    ); // Lắng nghe trạng thái Dark Mode
    final currency = ref.watch(currencyProvider);
    final timeZoneId = ref.watch(appTimeZoneProvider);
    final exchangeRate = ref.watch(vndExchangeRateProvider).value ?? 25400.0;
    final isBalanceHidden = ref.watch(hideBalanceProvider);
    final tradeSessionState = ref.watch(tradeSessionProvider);
    final isTradeAuthenticated = tradeSessionState.isAuthenticated;

    final palette = AppPalette.of(context);
    final bgColor = palette.background;
    final textColor = palette.ink;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final toolbarHeight =
        MediaQuery.sizeOf(context).width <= 400 && textScale > 1
        ? kToolbarHeight + (textScale - 1) * 24
        : kToolbarHeight;
    final filterControls = OrderFilterControls(
      currentTab: currentTab,
      currentFilter: currentFilter,
      isDark: isDark,
      onTabChanged: (tab) {
        ref.read(orderTabProvider.notifier).state = tab;
      },
      onFilterChanged: (filter) {
        ref.read(orderFilterProvider.notifier).state = filter;
      },
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: toolbarHeight,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Quản lý Giao dịch',
                maxLines: 2,
                softWrap: true,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: isTradeAuthenticated ? 'Đã đăng nhập' : 'Chưa đăng nhập',
              child: Semantics(
                label: isTradeAuthenticated ? 'Đã đăng nhập' : 'Chưa đăng nhập',
                child: Icon(
                  isTradeAuthenticated
                      ? Icons.verified_user_outlined
                      : Icons.lock_outline,
                  size: 18,
                  color: isTradeAuthenticated
                      ? palette.positive
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      body: NavigationContentFrame(
        child: Column(
          children: [
            if (currentTab == OrderTab.positions)
              TradeAccountControls(filterControls: filterControls)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: filterControls,
              ),

            Divider(height: 16, color: palette.border),

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
                timeZoneId,
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
    String timeZoneId,
  ) {
    final palette = AppPalette.forBrightness(isDark);
    if (currentTab == OrderTab.positions) {
      final tradeState = ref.watch(tradeSessionProvider);
      if (filter == 'SPOT') {
        return Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  'Giao dịch SPOT không hỗ trợ Vị thế mở.',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ),
            ),
          ],
        );
      }

      if (tradeState.isLoading) {
        return Center(child: CircularProgressIndicator(color: palette.ink));
      }

      if (tradeState.isAuthenticated) {
        final positionsAsyncValue = ref.watch(tradePositionsProvider);
        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: palette.ink,
                backgroundColor: palette.raised,
                onRefresh: () async => ref.invalidate(tradePositionsProvider),
                child: positionsAsyncValue.when(
                  skipLoadingOnReload: false,
                  loading: () => Center(
                    child: CircularProgressIndicator(color: palette.ink),
                  ),
                  error: (error, stack) => Center(
                    child: Text(
                      'Lỗi: $error',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: palette.negative),
                    ),
                  ),
                  data: (snapshot) {
                    final positions = filter == 'ALL'
                        ? snapshot.positions
                        : snapshot.positions
                              .where(
                                (position) =>
                                    position.instType.toUpperCase() == filter,
                              )
                              .toList(growable: false);
                    if (positions.isEmpty) {
                      return _buildEmptyState(
                        'Không có vị thế nào đang mở.',
                        isDark,
                      );
                    }
                    return ResponsiveOrderGrid(
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
                          .toList(growable: false),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      }

      final positionsAsyncValue = ref.watch(positionsFutureProvider);
      return Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: palette.ink,
              backgroundColor: palette.raised,
              onRefresh: () async => ref.invalidate(positionsFutureProvider),
              child: positionsAsyncValue.when(
                skipLoadingOnReload: false,
                loading: () => Center(
                  child: CircularProgressIndicator(color: palette.ink),
                ),
                error: (error, stack) => Center(
                  child: Text(
                    'Lỗi: $error',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: palette.negative),
                  ),
                ),
                data: (positions) {
                  if (positions.isEmpty) {
                    return _buildEmptyState(
                      'Không có vị thế nào đang mở.',
                      isDark,
                    );
                  }
                  return ResponsiveOrderGrid(
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
                        .toList(growable: false),
                  );
                },
              ),
            ),
          ),
        ],
      );
    } else {
      if (ref.watch(tradeSessionProvider).isLoading) {
        return Center(child: CircularProgressIndicator(color: palette.ink));
      }
      final ordersAsyncValue = ref.watch(ordersFutureProvider);
      final orderList = RefreshIndicator(
        color: palette.ink,
        backgroundColor: palette.raised,
        onRefresh: () async => ref.invalidate(ordersFutureProvider),
        child: ordersAsyncValue.when(
          skipLoadingOnReload: false,
          loading: () =>
              Center(child: CircularProgressIndicator(color: palette.ink)),
          error: (error, stack) => Center(
            child: Text(
              'Lỗi: $error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: palette.negative),
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
              children: orders
                  .map(
                    (order) => _buildOrderCard(
                      order,
                      currentTab,
                      isDark,
                      currency,
                      exchangeRate,
                      isBalanceHidden,
                      timeZoneId,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
      if (currentTab == OrderTab.pending) {
        return Column(
          children: [
            const TradeAccountControls(showCloseAll: false),
            Expanded(child: orderList),
          ],
        );
      }
      return orderList;
    }
  }

  Widget _buildEmptyState(String message, bool isDark) {
    final palette = AppPalette.forBrightness(isDark);
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Text(
            message,
            style: TextStyle(color: palette.muted, fontSize: 12),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        final labelWidget = Text(
          '$label:',
          softWrap: true,
          style: TextStyle(color: subtitleColor, fontSize: 12),
        );
        final amountWidget = notional == null
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
                  fontSize: 12,
                ),
              );

        if (effectiveWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labelWidget,
              const SizedBox(height: AppTokens.space2),
              Align(alignment: Alignment.centerRight, child: amountWidget),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: labelWidget),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: amountWidget,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInstrumentHeaderContents({
    required String baseCoin,
    required String instrumentLabel,
    required String instrumentType,
    required double instrumentFontSize,
    required Color iconBackgroundColor,
    required Color textColor,
    required Color badgeBackgroundColor,
    Key? instrumentTypeKey,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CryptoIcon(
          symbol: baseCoin,
          size: 20,
          backgroundColor: iconBackgroundColor,
          textColor: textColor,
          textSize: 10,
        ),
        const SizedBox(width: 6),
        Text(
          instrumentLabel,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: instrumentFontSize,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        if (instrumentType.isNotEmpty) ...[
          const SizedBox(width: 4),
          Container(
            key: instrumentTypeKey,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBackgroundColor,
              borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
            ),
            child: Text(
              instrumentType,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
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
    final palette = AppPalette.forBrightness(isDark);
    final posSide = position.posSide.toUpperCase();
    final isLong = posSide == 'LONG';

    final sideColor = posSide == 'NET'
        ? palette.ink
        : (isLong ? palette.positive : palette.negative);
    final sideText = posSide == 'NET' ? 'VỊ THẾ' : (isLong ? 'LONG' : 'SHORT');

    final pnl = double.tryParse(position.upl);
    final pnlColor = resolvePnlColor(pnl, palette, hidden: isBalanceHidden);
    final pnlSign = pnl == null ? '' : (pnl >= 0 ? '+' : '');
    final pnlFormatted = pnl == null
        ? '--'
        : NumberFormat("#,##0.00", "en_US").format(pnl.abs());

    final pnlRatio = double.tryParse(position.uplRatio);
    final pnlRatioPercent = pnlRatio == null
        ? '--'
        : '${pnlRatio >= 0 ? '+' : ''}${(pnlRatio * 100).toStringAsFixed(2)}%';
    final pnlRatioColor = resolvePnlColor(
      pnlRatio == null ? null : pnlRatio * 100,
      palette,
      hidden: isBalanceHidden,
    );

    final String baseCoin = position.instId.split('-').isNotEmpty
        ? position.instId.split('-').first
        : '?';
    final instrumentLabel = position.instId.split('-').take(2).join();
    final instrumentType = position.instType.toUpperCase();

    // Bảng màu cho Card
    final cardColor = palette.raised;
    final borderColor = palette.border;
    final textColor = palette.ink;
    final subtitleColor = palette.muted;
    final iconBgColor = palette.surface;

    return Card(
      key: ValueKey(positionActionIdentityKey(position.identity)),
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              key: const Key('position-card-header'),
              children: [
                Expanded(
                  flex: 5,
                  child: Align(
                    key: const Key('position-card-header-left'),
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _buildInstrumentHeaderContents(
                        baseCoin: baseCoin,
                        instrumentLabel: instrumentLabel,
                        instrumentType: instrumentType,
                        instrumentFontSize: 14,
                        iconBackgroundColor: iconBgColor,
                        textColor: textColor,
                        badgeBackgroundColor: palette.surface,
                        instrumentTypeKey: const Key(
                          'position-card-instrument-type',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.space2),
                Expanded(
                  flex: 3,
                  child: Align(
                    key: const Key('position-card-header-right'),
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sideColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                AppTokens.radiusSmall,
                              ),
                            ),
                            child: Text(
                              sideText,
                              style: TextStyle(
                                color: sideColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            key: const Key('position-card-leverage'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(
                                AppTokens.radiusSmall,
                              ),
                            ),
                            child: Text(
                              position.lever.isEmpty
                                  ? '--'
                                  : '${position.lever}x',
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (position.instType.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    '${position.direction.toUpperCase()} · ${position.size}',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                  Text(
                    '${position.instType} · ${position.mgnMode.toUpperCase()}',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                  if (position.marginCurrency.isNotEmpty)
                    Text(
                      'Ký quỹ ${position.marginCurrency}',
                      style: TextStyle(color: subtitleColor, fontSize: 12),
                    ),
                ],
              ),
            ],
            Divider(height: 16, color: palette.border),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lãi / Lỗ chưa thực hiện:',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
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
                        color: pnlRatioColor,
                        fontSize: 12,
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
            Divider(height: 16, color: palette.border),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Giá vào',
                        style: TextStyle(color: subtitleColor, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatAdaptiveNumber(position.avgPx),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
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
                        style: TextStyle(color: subtitleColor, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatAdaptiveNumber(position.markPx),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
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
                      Text(
                        'Thanh lý',
                        style: TextStyle(color: palette.warning, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        position.liqPx.isEmpty
                            ? '--'
                            : formatAdaptiveNumber(position.liqPx),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            PositionActionControls(position: position),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingOrderRow({
    required String rowName,
    required String label,
    required Widget value,
    required Color labelColor,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    return Row(
      key: Key('pending-order-row-$rowName'),
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$label:',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(color: labelColor, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.space3),
        Expanded(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: value,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingOrderCard(
    OkxOrder order,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
    String timeZoneId,
  ) {
    final palette = AppPalette.forBrightness(isDark);
    final isBuy = order.side.toLowerCase() == 'buy';
    final sideColor = isBuy ? palette.positive : palette.negative;
    final sideText = isBuy ? 'MUA' : 'BÁN';
    final timeString = formatOrderTimestamp(order.cTime, timeZoneId);
    final baseCoin = order.instId.split('-').first;
    final instrumentLabel = order.instId.split('-').take(2).join();
    final cardColor = palette.raised;
    final borderColor = palette.border;
    final textColor = palette.ink;
    final subtitleColor = palette.muted;
    final iconBgColor = palette.surface;
    final notional = resolveOrderNotional(order);
    final leverage = order.lever.isNotEmpty && order.lever != '0'
        ? order.lever
        : null;
    final instrumentType = order.instType.toUpperCase();

    return Card(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              key: const Key('pending-order-header'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Align(
                    key: const Key('pending-order-header-left'),
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CryptoIcon(
                            symbol: baseCoin,
                            size: 20,
                            backgroundColor: iconBgColor,
                            textColor: textColor,
                            textSize: 10,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            instrumentLabel,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          if (instrumentType.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              key: const Key('pending-order-instrument-type'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusSmall,
                                ),
                              ),
                              child: Text(
                                instrumentType,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: palette.ink,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.space2),
                Expanded(
                  flex: 2,
                  child: Align(
                    key: const Key('pending-order-header-right'),
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sideText,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: sideColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (leverage != null) ...[
                            const SizedBox(width: 4),
                            Container(
                              key: const Key('pending-order-leverage'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusSmall,
                                ),
                              ),
                              child: Text(
                                '${leverage}x',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: palette.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space2),
            _buildPendingOrderRow(
              rowName: 'timestamp',
              label: 'Thời gian',
              value: Text(
                timeString,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: subtitleColor, fontSize: 12),
              ),
              labelColor: subtitleColor,
            ),
            const SizedBox(height: AppTokens.space1),
            _buildPendingOrderRow(
              rowName: 'state',
              label: 'Trạng thái',
              value: Text(
                order.state.toUpperCase(),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              labelColor: subtitleColor,
            ),
            const SizedBox(height: AppTokens.space1),
            _buildPendingOrderRow(
              rowName: 'price',
              label: 'Giá',
              value: Text(
                formatAdaptiveNumber(order.px),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: textColor,
                ),
              ),
              labelColor: subtitleColor,
            ),
            const SizedBox(height: AppTokens.space1),
            _buildPendingOrderRow(
              rowName: 'quantity',
              label: 'KL',
              value: Text(
                formatAdaptiveNumber(order.sz),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: textColor,
                ),
              ),
              labelColor: subtitleColor,
            ),
            const SizedBox(height: AppTokens.space1),
            _buildPendingOrderRow(
              rowName: 'notional',
              label: notional?.source == TradeNotionalSource.filledOrder
                  ? 'Giá trị đã khớp'
                  : 'Giá trị lệnh',
              value: notional == null
                  ? Text(
                      '--',
                      maxLines: 1,
                      softWrap: false,
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
                      hidden: isBalanceHidden,
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
                        fontSize: 12,
                      ),
                    ),
              labelColor: subtitleColor,
              crossAxisAlignment: CrossAxisAlignment.start,
            ),
            if (isActiveLimitOrder(order))
              OrderCancellationControl(order: order),
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
    String timeZoneId,
  ) {
    if (currentTab == OrderTab.pending) {
      return _buildPendingOrderCard(
        order,
        isDark,
        currency,
        exchangeRate,
        isBalanceHidden,
        timeZoneId,
      );
    }

    final palette = AppPalette.forBrightness(isDark);
    final isBuy = order.side.toLowerCase() == 'buy';
    final sideColor = isBuy ? palette.positive : palette.negative;
    final sideText = isBuy ? 'MUA' : 'BÁN';

    final timeString = formatOrderTimestamp(order.cTime, timeZoneId);

    final String baseCoin = order.instId.split('-').isNotEmpty
        ? order.instId.split('-').first
        : '?';
    final instrumentLabel = order.instId.split('-').take(2).join();
    final instrumentType = order.instType.toUpperCase();
    final leverage = order.lever.isNotEmpty && order.lever != '0'
        ? order.lever
        : null;

    // Bảng màu
    final cardColor = palette.raised;
    final borderColor = palette.border;
    final textColor = palette.ink;
    final subtitleColor = palette.muted;
    final iconBgColor = palette.surface;
    final notional = resolveOrderNotional(order);

    return Card(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              key: const Key('history-order-header'),
              children: [
                Expanded(
                  flex: 5,
                  child: Align(
                    key: const Key('history-order-header-left'),
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _buildInstrumentHeaderContents(
                        baseCoin: baseCoin,
                        instrumentLabel: instrumentLabel,
                        instrumentType: instrumentType,
                        instrumentFontSize: 12,
                        iconBackgroundColor: iconBgColor,
                        textColor: textColor,
                        badgeBackgroundColor: palette.surface,
                        instrumentTypeKey: const Key(
                          'history-order-instrument-type',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.space2),
                Expanded(
                  flex: 2,
                  child: Align(
                    key: const Key('history-order-header-right'),
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sideText,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: sideColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (leverage != null) ...[
                            const SizedBox(width: 4),
                            Container(
                              key: const Key('history-order-leverage'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusSmall,
                                ),
                              ),
                              child: Text(
                                '${leverage}x',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: palette.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideAndTime = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.state.toUpperCase(),
                      style: TextStyle(
                        color: subtitleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space1),
                    Text(
                      timeString,
                      style: TextStyle(color: subtitleColor, fontSize: 12),
                    ),
                  ],
                );
                final values = Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Giá: ${formatAdaptiveNumber(order.px)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space1),
                    Text(
                      'KL: ${formatAdaptiveNumber(order.sz)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: textColor,
                      ),
                    ),
                  ],
                );

                if (constraints.maxWidth < 380) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      sideAndTime,
                      const SizedBox(height: AppTokens.space2),
                      Align(alignment: Alignment.centerRight, child: values),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: sideAndTime),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: values,
                      ),
                    ),
                  ],
                );
              },
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
            if (currentTab == OrderTab.pending && isActiveLimitOrder(order))
              OrderCancellationControl(order: order),
          ],
        ),
      ),
    );
  }
}
