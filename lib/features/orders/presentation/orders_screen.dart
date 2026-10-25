// File Name: orders_screen.dart
// File Path: lib/features/orders/presentation/orders_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/formatting/adaptive_number_format.dart';
import '../../../core/exchange/exchange_account_providers.dart';
import '../../../core/exchange/exchange_models.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/pnl_color.dart';
import '../../../core/timezone/app_time_zone.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../../core/widgets/exchange_icon.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import 'providers/order_provider.dart';
import 'providers/order_cancellation_flow_provider.dart';
import '../data/okx_order_model.dart';
import '../data/okx_position_model.dart';
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
import 'widgets/trade_account_controls.dart';
import '../../../core/exchange/binance_history_scan.dart';

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
  bool _manualRefreshInFlight = false;
  bool _historyActive = false;
  BinanceAccountHistoryController? _historyController;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final currentTab = ref.read(orderTabProvider);
      final currentFilter = ref.read(orderFilterProvider);
      if (currentTab == OrderTab.history) return;
      if (currentTab == OrderTab.positions && currentFilter == 'SPOT') return;

      if (currentTab == OrderTab.positions) {
        _invalidatePositionSources(currentFilter);
      } else {
        final request = CombinedOrderReadRequest(
          type: CombinedOrderReadType.pending,
          filter: currentFilter,
        );
        _invalidateOrderSources(request);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    final historyController = _historyController;
    if (_historyActive && historyController != null) {
      historyController.leaveHistory();
    }
    super.dispose();
  }

  Future<void> _refreshCurrentRead() async {
    final currentTab = ref.read(orderTabProvider);
    final currentFilter = ref.read(orderFilterProvider);
    if (currentTab == OrderTab.positions && currentFilter == 'SPOT') return;

    if (_manualRefreshInFlight) return;

    setState(() => _manualRefreshInFlight = true);
    try {
      if (currentTab == OrderTab.positions) {
        _invalidatePositionSources(currentFilter, force: true);
      } else {
        final request = CombinedOrderReadRequest(
          type: currentTab == OrderTab.pending
              ? CombinedOrderReadType.pending
              : CombinedOrderReadType.history,
          filter: currentFilter,
        );
        if (currentTab == OrderTab.history) {
          ref.read(binanceAccountHistoryProvider.notifier).refreshHistory();
        }
        _invalidateOrderSources(request, force: true);
      }
      await Future<void>.delayed(Duration.zero);
    } catch (_) {
      // The current tab provider renders its read error.
    } finally {
      if (mounted) setState(() => _manualRefreshInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFilter = ref.watch(orderFilterProvider);
    final currentTab = ref.watch(orderTabProvider);
    _syncHistoryLifecycle(currentTab);
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
        actions: [
          ManualRefreshButton(
            buttonKey: const Key('orders-manual-refresh'),
            onRefresh:
                currentTab == OrderTab.positions && currentFilter == 'SPOT'
                ? null
                : _refreshCurrentRead,
            isBusy: _manualRefreshInFlight,
          ),
        ],
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

  void _syncHistoryLifecycle(OrderTab tab) {
    final shouldRun = tab == OrderTab.history;
    if (_historyActive == shouldRun) return;
    _historyActive = shouldRun;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(binanceAccountHistoryProvider.notifier);
      _historyController = controller;
      if (shouldRun) {
        controller.enterHistory();
      } else {
        controller.leaveHistory();
      }
    });
  }

  void _invalidatePositionSources(String filter, {bool force = false}) {
    final current = ref.read(combinedExchangePositionsProvider(filter));
    final okx = current.sources.where(
      (source) => source.source == ExchangeSource.okx,
    );
    final binance = current.sources.where(
      (source) => source.source == ExchangeSource.binance,
    );
    if (okx.isEmpty ||
        (!okx.first.isLoading && (force || !okx.first.isTerminalFailure))) {
      ref.invalidate(okxExchangePositionsSourceProvider(filter));
    }
    if (filter != 'SPOT' &&
        filter != 'MARGIN' &&
        (binance.isEmpty ||
            (!binance.first.isLoading &&
                (force || !binance.first.isTerminalFailure)))) {
      ref.invalidate(binanceExchangePositionsSourceProvider(filter));
    }
  }

  void _invalidateOrderSources(
    CombinedOrderReadRequest request, {
    bool force = false,
  }) {
    final current = ref.read(combinedExchangeOrdersProvider(request));
    final okx = current.sources.where(
      (source) => source.source == ExchangeSource.okx,
    );
    final spot = current.sources.where(
      (source) =>
          source.source == ExchangeSource.binance &&
          source.product == ExchangeProduct.spot,
    );
    final futures = current.sources.where(
      (source) =>
          source.source == ExchangeSource.binance &&
          source.product == ExchangeProduct.swap,
    );
    if (okx.isEmpty ||
        (!okx.first.isLoading && (force || !okx.first.isTerminalFailure))) {
      ref.invalidate(okxExchangeOrdersSourceProvider(request));
    }
    if (request.type != CombinedOrderReadType.pending) return;
    if ((request.filter == 'ALL' || request.filter == 'SPOT') &&
        (spot.isEmpty ||
            (!spot.first.isLoading &&
                (force || !spot.first.isTerminalFailure)))) {
      ref.invalidate(binanceSpotPendingOrdersSourceProvider(request.filter));
    }
    if (request.filter == 'ALL' ||
        request.filter == 'SWAP' ||
        request.filter == 'FUTURES') {
      if (futures.isEmpty ||
          (!futures.first.isLoading &&
              (force || !futures.first.isTerminalFailure))) {
        ref.invalidate(
          binanceFuturesPendingOrdersSourceProvider(request.filter),
        );
      }
    }
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

      final result = ref.watch(combinedExchangePositionsProvider(filter));
      return _buildCombinedRowsView<ExchangePosition>(
        rows: result.rows,
        isPartial: result.isPartial,
        warnings: result.sources
            .where((source) => source.isApplicable && source.error != null)
            .map((source) => source.error!)
            .toList(growable: false),
        emptyMessage: result.isPartial
            ? 'Some position data is still loading or unavailable.'
            : 'No open positions.',
        isDark: isDark,
        onRefresh: _refreshCurrentRead,
        itemBuilder: (position) => _buildExchangePositionCard(
          position,
          isDark,
          currency,
          exchangeRate,
          isBalanceHidden,
        ),
      );
    }

    final request = CombinedOrderReadRequest(
      type: currentTab == OrderTab.pending
          ? CombinedOrderReadType.pending
          : CombinedOrderReadType.history,
      filter: filter,
    );
    final result = ref.watch(combinedExchangeOrdersProvider(request));
    final history = currentTab == OrderTab.history
        ? ref.watch(binanceAccountHistoryProvider)
        : const BinanceAccountHistoryState();
    final historyRows = currentTab == OrderTab.history
        ? _historyRowsForFilter(history, filter)
        : const <ExchangeOrder>[];
    final rowsByIdentity = <String, ExchangeOrder>{
      for (final order in result.rows) order.identityKey: order,
      for (final order in historyRows) order.identityKey: order,
    };
    final rows = rowsByIdentity.values.toList()
      ..sort((left, right) {
        final byTime = (right.createdAtMilliseconds ?? 0).compareTo(
          left.createdAtMilliseconds ?? 0,
        );
        return byTime != 0
            ? byTime
            : left.identityKey.compareTo(right.identityKey);
      });
    final scanPartial =
        currentTab == OrderTab.history &&
        _historyCoverageIsPartial(history, filter);
    final warnings = <String>[
      ...result.sources
          .where((source) => source.isApplicable && source.error != null)
          .map((source) => source.error!),
      if (scanPartial)
        'Binance history coverage is incomplete. Captured trades remain visible while symbol reads continue or retry.',
    ];
    final orderList = _buildCombinedRowsView<ExchangeOrder>(
      rows: rows,
      isPartial: result.isPartial || scanPartial,
      warnings: warnings,
      emptyMessage: result.isPartial || scanPartial
          ? 'Some exchange data is still loading or unavailable; an empty result is not confirmed.'
          : currentTab == OrderTab.pending
          ? 'No pending orders.'
          : 'No trades were found in the captured history.',
      isDark: isDark,
      onRefresh: _refreshCurrentRead,
      itemBuilder: (order) => _buildExchangeOrderCard(
        order,
        currentTab,
        isDark,
        currency,
        exchangeRate,
        isBalanceHidden,
        timeZoneId,
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
    if (currentTab == OrderTab.history) {
      return Column(
        children: [
          _buildHistoryProgress(history, filter, isDark, timeZoneId),
          Expanded(child: orderList),
        ],
      );
    }
    return orderList;
  }

  Widget _buildCombinedRowsView<T>({
    required List<T> rows,
    required bool isPartial,
    required List<String> warnings,
    required String emptyMessage,
    required bool isDark,
    required Future<void> Function() onRefresh,
    required Widget Function(T item) itemBuilder,
  }) {
    final palette = AppPalette.forBrightness(isDark);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = orderGridColumnCountForWidth(constraints.maxWidth);
        return RefreshIndicator(
          color: palette.ink,
          backgroundColor: palette.raised,
          onRefresh: onRefresh,
          child: CustomScrollView(
            key: const Key('combined-order-rows-scroll'),
            slivers: [
              if (isPartial)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Semantics(
                      liveRegion: true,
                      child: Container(
                        key: const Key('combined-orders-partial-warning'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: palette.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusSmall,
                          ),
                          border: Border.all(
                            color: palette.warning.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Partial exchange data'),
                            for (final warning in warnings.take(3))
                              Text(
                                warning,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        emptyMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ),
                  ),
                )
              else if (columns == 1)
                SliverPadding(
                  padding: const EdgeInsets.all(AppTokens.space3),
                  sliver: SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.space2),
                      child: itemBuilder(rows[index]),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(AppTokens.space3),
                  sliver: SliverList.builder(
                    itemCount: (rows.length + columns - 1) ~/ columns,
                    itemBuilder: (context, rowIndex) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.space3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var column = 0; column < columns; column++) ...[
                            if (column > 0)
                              const SizedBox(width: AppTokens.space3),
                            Expanded(
                              child: rowIndex * columns + column < rows.length
                                  ? itemBuilder(
                                      rows[rowIndex * columns + column],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<ExchangeOrder> _historyRowsForFilter(
    BinanceAccountHistoryState history,
    String filter,
  ) {
    final rows = <ExchangeOrder>[];
    if (filter == 'ALL' || filter == 'SPOT') {
      rows.addAll(history.spot?.rows ?? const <ExchangeOrder>[]);
    }
    if (filter == 'ALL' || filter == 'SWAP' || filter == 'FUTURES') {
      rows.addAll(
        (history.futures?.rows ?? const <ExchangeOrder>[]).where((order) {
          if (filter == 'ALL') return true;
          return order.product?.name.toUpperCase() == filter;
        }),
      );
    }
    return rows;
  }

  bool _historyCoverageIsPartial(
    BinanceAccountHistoryState history,
    String filter,
  ) {
    if (filter == 'MARGIN') return false;
    final needsSpot = filter == 'ALL' || filter == 'SPOT';
    final needsFutures =
        filter == 'ALL' || filter == 'SWAP' || filter == 'FUTURES';
    return (needsSpot &&
            (history.spot == null ||
                !history.spot!.allCapturedSymbolsComplete ||
                history.spotError != null)) ||
        (needsFutures &&
            (history.futures == null ||
                !history.futures!.allCapturedSymbolsComplete ||
                history.futuresError != null));
  }

  Widget _buildHistoryProgress(
    BinanceAccountHistoryState history,
    String filter,
    bool isDark,
    String timeZoneId,
  ) {
    final palette = AppPalette.forBrightness(isDark);
    final spot = history.spot;
    final futures = history.futures;
    final isRunning =
        spot?.state == BinanceHistoryScanState.running ||
        futures?.state == BinanceHistoryScanState.running;
    String progressLabel(BinanceHistoryScanProgress? progress, String? error) {
      if (error != null) return error;
      if (progress == null) return 'Waiting to start';
      final counts =
          '${progress.completedSymbols}/${progress.totalSymbols} complete · '
          '${progress.pendingSymbols} pending · ${progress.failedSymbols} failed';
      final retry = progress.retryAt;
      final retryLabel = retry == null
          ? ''
          : retry.isAfter(AppTimeZone.now(timeZoneId))
          ? ' · retry at ${DateFormat('HH:mm:ss').format(AppTimeZone.fromEpochMilliseconds(timeZoneId, retry.millisecondsSinceEpoch))}'
          : ' · retry available';
      final reason = progress.message == null ? '' : ' · ${progress.message}';
      return '$counts · ${progress.state.name}$retryLabel$reason';
    }

    Widget productProgress(
      String label,
      BinanceHistoryScanProgress? progress,
      String? error,
    ) {
      final coverage = progress?.coverageNotice;
      final description = [
        label,
        progressLabel(progress, error),
        if (coverage != null && coverage.isNotEmpty) coverage,
      ].join('. ');
      return Semantics(
        liveRegion: true,
        label: description,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label · ${progressLabel(progress, error)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: 11),
            ),
            if (coverage != null && coverage.isNotEmpty)
              Text(
                coverage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 10),
              ),
          ],
        ),
      );
    }

    final progressContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        productProgress('Binance Spot', spot, history.spotError),
        productProgress('Binance Futures', futures, history.futuresError),
        if (filter == 'MARGIN')
          Text(
            'Binance Margin history is not supported.',
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
        if (isRunning)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(
              key: Key('binance-history-running'),
              minHeight: 2,
            ),
          ),
      ],
    );
    final scanControl = TextButton(
      key: const Key('binance-history-scan-control'),
      onPressed: () {
        final controller = ref.read(binanceAccountHistoryProvider.notifier);
        if (isRunning) {
          controller.leaveHistory();
        } else if (spot?.state == BinanceHistoryScanState.complete &&
            futures?.state == BinanceHistoryScanState.complete) {
          controller.refreshHistory();
        } else {
          controller.resumeHistory();
        }
      },
      child: Text(
        isRunning
            ? 'Cancel'
            : spot?.state == BinanceHistoryScanState.complete &&
                  futures?.state == BinanceHistoryScanState.complete
            ? 'Scan again'
            : 'Resume',
      ),
    );

    return Container(
      key: const Key('binance-history-progress'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      decoration: BoxDecoration(
        color: palette.raised,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                progressContent,
                Align(alignment: Alignment.centerRight, child: scanControl),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: progressContent),
              scanControl,
            ],
          );
        },
      ),
    );
  }

  Widget _buildExchangePositionCard(
    ExchangePosition position,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
  ) {
    final native = position.nativeRecord;
    if (position.source == ExchangeSource.okx && native is OkxPosition) {
      return _buildPositionCard(
        native,
        isDark,
        currency,
        exchangeRate,
        isBalanceHidden,
      );
    }
    final palette = AppPalette.forBrightness(isDark);
    final direction = position.effectiveDirection;
    final isLong = direction == ExchangePositionSide.long;
    final sideText = switch (direction) {
      ExchangePositionSide.long => 'LONG',
      ExchangePositionSide.short => 'SHORT',
      ExchangePositionSide.net => 'NET',
      _ => 'SIDE UNKNOWN',
    };
    final sideColor = direction == null
        ? palette.muted
        : isLong
        ? palette.positive
        : palette.negative;
    final pnl = position.unrealizedPnl.value;
    final pnlAmount = pnl?.amount.finiteDouble;
    final pnlColor = resolvePnlColor(
      pnlAmount,
      palette,
      hidden: isBalanceHidden,
    );
    final symbol = position.symbol;
    final separator = symbol.indexOf('-');
    final base = separator > 0 ? symbol.substring(0, separator) : symbol;
    final product = position.product?.name.toUpperCase() ?? 'UNKNOWN PRODUCT';
    final amount = position.positionAmount.value;
    final mark = position.markPrice.value;
    final entry = position.entryPrice.value;
    final leverage = position.leverage.value;
    return Card(
      key: ValueKey('exchange-position:${position.identityKey}'),
      elevation: 0,
      color: palette.raised,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CryptoIcon(
                  symbol: base,
                  size: 28,
                  backgroundColor: palette.surface,
                  textColor: palette.ink,
                  textSize: 11,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$product · ${position.marginMode.value ?? 'mode unavailable'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ExchangeIcon(source: position.source, size: 18),
                const SizedBox(width: 6),
                Text(
                  sideText,
                  style: TextStyle(
                    color: sideColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  'Qty ${amount?.text ?? '--'}',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                Text(
                  'Entry ${entry?.text ?? '--'}',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                Text(
                  'Mark ${mark?.text ?? '--'}',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                Text(
                  'Leverage ${leverage?.text ?? '--'}x',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                if (position.marginCurrency.value != null)
                  Text(
                    'Margin ${position.marginCurrency.value}',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
              ],
            ),
            Divider(height: 16, color: palette.border),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Unrealized PnL',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                Text(
                  pnl == null
                      ? '--'
                      : isBalanceHidden
                      ? '******'
                      : '${pnl.amount.text} ${pnl.currency}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: pnlColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExchangeOrderCard(
    ExchangeOrder order,
    OrderTab currentTab,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
    String timeZoneId,
  ) {
    final native = order.okxActionDto;
    if (order.source == ExchangeSource.okx && native is OkxOrder) {
      final nativeCard = currentTab == OrderTab.pending
          ? _buildPendingOrderCard(
              native,
              isDark,
              currency,
              exchangeRate,
              isBalanceHidden,
              timeZoneId,
              actionOrder: order,
            )
          : _buildOrderCard(
              native,
              currentTab,
              isDark,
              currency,
              exchangeRate,
              isBalanceHidden,
              timeZoneId,
              actionOrder: order,
            );
      return nativeCard;
    }
    final palette = AppPalette.forBrightness(isDark);
    final isBuy = order.side.toLowerCase() == 'buy';
    final sideColor = isBuy ? palette.positive : palette.negative;
    final timestamp = order.createdAtMilliseconds;
    final time = timestamp == null
        ? '--'
        : formatOrderTimestamp(timestamp.toString(), timeZoneId);
    final separator = order.symbol.indexOf('-');
    final base = separator > 0
        ? order.symbol.substring(0, separator)
        : order.symbol;
    final product = order.product?.name.toUpperCase() ?? 'UNIFIED';
    final pending = currentTab == OrderTab.pending;
    final notional = resolveExchangeOrderNotional(order, pending: pending);
    final price = order.price?.value;
    final quantity = pending
        ? order.quantity.value
        : order.executedQuantity.value;
    return Card(
      key: ValueKey('exchange-order:${order.identityKey}'),
      elevation: 0,
      color: palette.raised,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CryptoIcon(
                  symbol: base,
                  size: 26,
                  backgroundColor: palette.surface,
                  textColor: palette.ink,
                  textSize: 10,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$product · ${order.kind.name.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ExchangeIcon(source: order.source, size: 18),
                const SizedBox(width: 6),
                Text(
                  isBuy ? 'BUY' : 'SELL',
                  style: TextStyle(
                    color: sideColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  order.status.toUpperCase(),
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                Text(
                  time,
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                Text(
                  'Price ${price == null ? '--' : '${price.amount.text} ${price.currency}'}',
                  style: TextStyle(color: palette.ink, fontSize: 12),
                ),
                Text(
                  'Qty ${quantity?.text ?? '--'}',
                  style: TextStyle(color: palette.ink, fontSize: 12),
                ),
                if (pending && order.executedQuantity.value != null)
                  Text(
                    'Filled ${order.executedQuantity.value!.text}',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildNotionalRow(
              label: notional?.source == TradeNotionalSource.filledOrder
                  ? 'Filled value'
                  : 'Order estimate',
              notional: notional,
              currency: currency,
              exchangeRate: exchangeRate,
              isHidden: isBalanceHidden,
              textColor: palette.ink,
              subtitleColor: palette.muted,
            ),
            if (pending) OrderCancellationControl(order: order),
          ],
        ),
      ),
    );
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
            : !const {'USD', 'USDT'}.contains(notional.currency.toUpperCase())
            ? Text(
                isHidden
                    ? '******'
                    : '${formatAdaptiveNumber(notional.usdAmount.toString())} ${notional.currency}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
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
      key: ValueKey(_nativePositionDisplayKey(position)),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildInstrumentHeaderContents(
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
                        ],
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
                          const Tooltip(
                            message: 'OKX Unified',
                            child: ExchangeIcon(
                              source: ExchangeSource.okx,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 4),
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
          ],
        ),
      ),
    );
  }

  String _nativePositionDisplayKey(OkxPosition position) {
    if (position.positionId.isNotEmpty) {
      return 'native-pos:${position.positionId}';
    }
    return jsonEncode([
      position.instId,
      position.instType,
      position.posSide,
      position.mgnMode,
      position.marginCurrency,
      position.positionCurrency,
    ]);
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
    String timeZoneId, {
    ExchangeOrder? actionOrder,
  }) {
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
                          const Tooltip(
                            message: 'OKX Unified',
                            child: ExchangeIcon(
                              source: ExchangeSource.okx,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 4),
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
            if (actionOrder != null && isActiveLimitOrder(order))
              OrderCancellationControl(order: actionOrder),
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
    String timeZoneId, {
    ExchangeOrder? actionOrder,
  }) {
    if (currentTab == OrderTab.pending) {
      return _buildPendingOrderCard(
        order,
        isDark,
        currency,
        exchangeRate,
        isBalanceHidden,
        timeZoneId,
        actionOrder: actionOrder,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildInstrumentHeaderContents(
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
                        ],
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
                          const Tooltip(
                            message: 'OKX Unified',
                            child: ExchangeIcon(
                              source: ExchangeSource.okx,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 4),
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
            if (currentTab == OrderTab.pending &&
                actionOrder != null &&
                isActiveLimitOrder(order))
              OrderCancellationControl(order: actionOrder),
          ],
        ),
      ),
    );
  }
}
