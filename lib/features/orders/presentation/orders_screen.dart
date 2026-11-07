import '../../../core/widgets/scope_bar.dart';
import '../../../core/widgets/account_state_view.dart';
// File Name: orders_screen.dart
// File Path: lib/features/orders/presentation/orders_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/backend_features.dart';
import '../../../core/exchange/exchange_models.dart';
import '../../../core/exchange/exchange_registry.dart';
import '../../../core/exchange/exchange_scope.dart';
import '../../../core/exchange/scoped_read.dart';
import '../../../core/formatting/adaptive_number_format.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/pnl_color.dart';
import '../../../core/timezone/app_time_zone.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import 'providers/order_provider.dart';
import 'providers/order_cancellation_flow_provider.dart';
import '../data/okx_order_model.dart';
import 'providers/trade_session_provider.dart';
import 'package:intl/intl.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Thêm import này để lấy trạng thái Dark Mode
import '../../portfolio/presentation/widgets/portfolio_currency_amount.dart';
import '../../settings/presentation/settings_screen.dart'
    show currencyProvider, vndExchangeRateProvider;
import 'widgets/order_filter_controls.dart';
import 'widgets/margin_account_card.dart';
import '../../../exchanges/binance/binance_adapter.dart';
import '../../../exchanges/binance/binance_estimated_pnl.dart';
import 'widgets/order_notional.dart';
import 'widgets/order_cancellation_control.dart';
import 'widgets/responsive_order_grid.dart';
import 'widgets/trade_account_controls.dart';

String _instrumentBase(InstrumentKey key) =>
    key.base ??
    (key.exchange == ExchangeId.okx
        ? key.nativeId.split('-').first
        : key.nativeId);
String _instrumentLabel(InstrumentKey key) =>
    key.exchange != ExchangeId.okx && key.base != null && key.quote != null
    ? '${key.base}/${key.quote}'
    : (key.exchange == ExchangeId.okx
          ? key.nativeId.split('-').take(2).join()
          : key.nativeId);

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
  ExchangeScope? _costScope;
  ExchangeScope? _activeCostScope;
  bool _costFinished = false;

  void _startCost(ExchangeScope scope, AccountSnapshot account) {
    _costScope = scope;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ref.read(exchangeScopeProvider) != scope) return;
      try {
        final controller = await ref.read(binanceCostControllerProvider.future);
        await controller.run(account);
      } catch (_) {
        // History failure does not affect account data.
      } finally {
        if (mounted && ref.read(exchangeScopeProvider) == scope) {
          setState(() => _costFinished = true);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final currentTab = ref.read(orderTabProvider);
      final currentFilter = ref.read(orderFilterProvider);
      if (currentTab == OrderTab.positions && currentFilter == 'SPOT') return;

      final scope = ref.read(exchangeScopeProvider);
      final currentRead = currentTab == OrderTab.positions
          ? ref.read(scopedPositionsProvider(scope))
          : ref.read(scopedOrdersProvider(scope));
      if (currentRead.isLoading ||
          isTerminalAccountFailure(
            ref
                .read(exchangeRegistryProvider)
                .firstWhere(
                  (entry) => entry.profile.connectionId == scope.connectionId,
                ),
            currentRead.asError?.error,
          )) {
        return;
      }

      if (currentTab == OrderTab.positions &&
          scope.exchange == ExchangeId.binance &&
          (currentFilter == 'ALL' || currentFilter == 'MARGIN') &&
          currentRead.asData != null) {
        final accountRead = ref.read(scopedAccountProvider(scope));
        if (accountRead.isLoading ||
            isTerminalAccountFailure(
              ref
                  .read(exchangeRegistryProvider)
                  .firstWhere(
                    (entry) => entry.profile.connectionId == scope.connectionId,
                  ),
              accountRead.asError?.error,
            ))
          return;
      }
      _invalidateCurrentRead(scope, currentTab);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCurrentRead() async {
    final currentTab = ref.read(orderTabProvider);
    final currentFilter = ref.read(orderFilterProvider);
    if (currentTab == OrderTab.positions && currentFilter == 'SPOT') return;

    final scope = ref.read(exchangeScopeProvider);
    final currentRead = currentTab == OrderTab.positions
        ? ref.read(scopedPositionsProvider(scope))
        : ref.read(scopedOrdersProvider(scope));
    if (currentRead.isLoading || _manualRefreshInFlight) return;
    if (currentTab == OrderTab.positions &&
        scope.exchange == ExchangeId.binance &&
        (currentFilter == 'ALL' || currentFilter == 'MARGIN') &&
        currentRead.asData != null &&
        ref.read(scopedAccountProvider(scope)).isLoading)
      return;

    setState(() => _manualRefreshInFlight = true);
    try {
      if (currentTab == OrderTab.positions) {
        _invalidateCurrentRead(scope, currentTab);
        await ref.read(scopedPositionsProvider(scope).future);
      } else {
        _invalidateCurrentRead(scope, currentTab);
        await ref.read(scopedOrdersProvider(scope).future);
      }
    } catch (_) {
      // The current tab provider renders its read error.
    } finally {
      if (mounted &&
          scope.exchange == ExchangeId.binance &&
          (currentFilter == 'ALL' || currentFilter == 'MARGIN') &&
          ref.read(exchangeScopeProvider) == scope) {
        final account = ref.read(scopedAccountProvider(scope)).valueOrNull;
        if (account != null) _startCost(scope, account);
      }
      if (mounted) setState(() => _manualRefreshInFlight = false);
    }
  }

  void _invalidateCurrentRead(ExchangeScope scope, OrderTab tab) {
    final adapter = ref
        .read(exchangeRegistryProvider)
        .firstWhere(
          (entry) =>
              entry.profile.connectionId == scope.connectionId &&
              entry.profile.exchange == scope.exchange,
        )
        .adapter;
    if (tab == OrderTab.positions) {
      adapter.invalidatePositions(ref.invalidate);
      ref.invalidate(scopedPositionsProvider(scope));
      if (scope.exchange == ExchangeId.binance &&
          (ref.read(orderFilterProvider) == 'ALL' ||
              ref.read(orderFilterProvider) == 'MARGIN')) {
        adapter.invalidateAccount(ref.invalidate);
        ref.invalidate(scopedAccountProvider(scope));
      }
    } else {
      adapter.invalidateOrders(ref.invalidate);
      ref.invalidate(scopedOrdersProvider(scope));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeScope = ref.watch(exchangeScopeProvider);
    if (_activeCostScope != activeScope) {
      _activeCostScope = activeScope;
      _costScope = null;
      _costFinished = false;
    }
    final currentFilter = ref.watch(orderFilterProvider);
    final currentTab = ref.watch(orderTabProvider);
    final isDark = ref.watch(
      isDarkModeProvider,
    ); // Lắng nghe trạng thái Dark Mode
    final currency = ref.watch(currencyProvider);
    final timeZoneId = ref.watch(appTimeZoneProvider);
    final exchangeRate = ref.watch(vndExchangeRateProvider).value ?? 25400.0;
    final isBalanceHidden = ref.watch(hideBalanceProvider);
    final scope = ref.watch(exchangeScopeProvider);
    final backendFeaturesEnabled =
        ref.watch(backendFeaturesEnabledProvider) &&
        scope.exchange == ExchangeId.okx;
    final tradeSessionState = backendFeaturesEnabled
        ? ref.watch(tradeSessionProvider)
        : null;
    final isTradeAuthenticated = tradeSessionState?.isAuthenticated ?? false;
    final isCurrentReadLoading = switch (currentTab) {
      OrderTab.positions when currentFilter == 'SPOT' => false,
      OrderTab.positions => ref.watch(scopedPositionsProvider(scope)).isLoading,
      _ => ref.watch(scopedOrdersProvider(scope)).isLoading,
    };

    final palette = AppPalette.of(context);
    final bgColor = palette.background;
    final textColor = palette.ink;
    final filterControls = OrderFilterControls(
      binanceProducts: scope.exchange == ExchangeId.binance
          ? ref
                .watch(exchangeRegistryProvider)
                .firstWhere(
                  (entry) =>
                      entry.profile.connectionId == scope.connectionId &&
                      entry.profile.exchange == scope.exchange,
                )
                .adapter
                .capabilities
                .readableProducts
                .where(
                  (product) =>
                      ref.watch(binanceSpotMarginAvailableProvider) ||
                      product == 'SWAP',
                )
                .toList()
          : null,
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
      body: SafeArea(
        child: NavigationContentFrame(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Lệnh',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (backendFeaturesEnabled)
                          Tooltip(
                            message: isTradeAuthenticated
                                ? 'Đã đăng nhập'
                                : 'Chưa đăng nhập',
                            child: Semantics(
                              label: isTradeAuthenticated
                                  ? 'Đã đăng nhập'
                                  : 'Chưa đăng nhập',
                              child: Icon(
                                isTradeAuthenticated
                                    ? Icons.verified_user_outlined
                                    : Icons.lock_outline,
                                size: 18,
                                color: isTradeAuthenticated
                                    ? palette.positive
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ManualRefreshButton(
                          buttonKey: const Key('orders-manual-refresh'),
                          onRefresh:
                              currentTab == OrderTab.positions &&
                                  currentFilter == 'SPOT'
                              ? null
                              : _refreshCurrentRead,
                          isBusy:
                              _manualRefreshInFlight || isCurrentReadLoading,
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: ScopeBar(),
                  ),
                  if (currentTab == OrderTab.positions &&
                      backendFeaturesEnabled)
                    TradeAccountControls(filterControls: filterControls)
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: filterControls,
                    ),

                  if (currentTab == OrderTab.positions)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Vị thế của ${ref.watch(exchangeRegistryProvider).firstWhere((entry) => entry.profile.connectionId == scope.connectionId).profile.label} / Chính',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  Divider(height: 16, color: palette.border),
                ]),
              ),
            ],
            body: _buildBodyContent(
              context,
              currentTab,
              currentFilter,
              isDark,
              currency,
              exchangeRate,
              isBalanceHidden,
              timeZoneId,
              backendFeaturesEnabled,
            ),
          ),
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
    bool backendFeaturesEnabled,
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

      final positionsAsyncValue = ref.watch(
        scopedPositionsProvider(ref.watch(exchangeScopeProvider)),
      );
      return Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: palette.ink,
              backgroundColor: palette.raised,
              onRefresh: _refreshCurrentRead,
              child: positionsAsyncValue.when(
                skipLoadingOnReload: false,
                loading: () => Center(
                  child: CircularProgressIndicator(color: palette.ink),
                ),
                error: (error, stack) => AccountStateView.fromError(
                  error: error,
                  registration: ref
                      .read(exchangeRegistryProvider)
                      .firstWhere(
                        (entry) =>
                            entry.profile.connectionId ==
                            ref.read(exchangeScopeProvider).connectionId,
                      ),
                  onRetry: _refreshCurrentRead,
                ),
                data: (positions) {
                  final scope = ref.watch(exchangeScopeProvider);
                  final showMargin =
                      scope.exchange == ExchangeId.binance &&
                      (filter == 'ALL' || filter == 'MARGIN');
                  final accountAsync = showMargin
                      ? ref.watch(scopedAccountProvider(scope))
                      : null;
                  final account = accountAsync?.valueOrNull;
                  if (_costScope != scope) _costFinished = false;
                  if (account != null && _costScope != scope)
                    _startCost(scope, account);
                  final costView = showMargin
                      ? ref.watch(binanceCostStateProvider).valueOrNull
                      : null;
                  final rows =
                      account?.marginRows ?? const <MarginAccountRow>[];
                  final marginUnavailable =
                      account?.walletResults.any(
                        (result) =>
                            !result.available &&
                            (result.wallet == 'Cross Margin' ||
                                result.wallet == 'Isolated Margin'),
                      ) ??
                      false;
                  final notice = marginUnavailable
                      ? PartialAccountNotice(
                          account: account!,
                          spotMarginAvailable: ref.watch(
                            binanceSpotMarginAvailableProvider,
                          ),
                        )
                      : null;
                  if (positions.isEmpty && rows.isEmpty) {
                    if (accountAsync != null) {
                      if (accountAsync.isLoading && account == null) {
                        return _scrollableState(
                          Center(
                            child: CircularProgressIndicator(
                              color: palette.ink,
                            ),
                          ),
                        );
                      }
                      if (accountAsync.hasError) {
                        return _scrollableState(
                          AccountStateView.fromError(
                            error: accountAsync.error!,
                            registration: ref
                                .read(exchangeRegistryProvider)
                                .firstWhere(
                                  (entry) =>
                                      entry.profile.connectionId ==
                                      scope.connectionId,
                                ),
                            onRetry: _refreshCurrentRead,
                          ),
                        );
                      }
                    }
                    if (notice != null) return _scrollableState(notice);
                    return _buildEmptyState(
                      scope.exchange == ExchangeId.okx
                          ? 'Không có vị thế nào đang mở.'
                          : 'Chưa có vị thế trên ${ref.watch(exchangeRegistryProvider).firstWhere((entry) => entry.profile.connectionId == scope.connectionId).profile.label}',
                      isDark,
                    );
                  }
                  return ResponsiveOrderGrid(
                    children: [
                      if (notice != null) notice,
                      ...rows.map((row) {
                        final estimate =
                            account != null &&
                                costView != null &&
                                !isBalanceHidden
                            ? estimatedMargin(
                                costView,
                                _costFinished,
                                row,
                                account,
                              )
                            : null;
                        final vnd = currency == 'VNĐ';
                        return MarginAccountCard(
                          row: row,
                          estimateText: estimate == null
                              ? null
                              : estimatedPnlText(
                                  estimate,
                                  rate: vnd ? exchangeRate : 1,
                                  unit: vnd ? 'đ' : 'USDT',
                                ),
                        );
                      }),
                      ...positions
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
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      );
    } else {
      final ordersAsyncValue = ref.watch(
        scopedOrdersProvider(ref.watch(exchangeScopeProvider)),
      );
      final orderList = RefreshIndicator(
        color: palette.ink,
        backgroundColor: palette.raised,
        onRefresh: _refreshCurrentRead,
        child: ordersAsyncValue.when(
          skipLoadingOnReload: false,
          loading: () =>
              Center(child: CircularProgressIndicator(color: palette.ink)),
          error: (error, stack) => AccountStateView.fromError(
            error: error,
            registration: ref
                .read(exchangeRegistryProvider)
                .firstWhere(
                  (entry) =>
                      entry.profile.connectionId ==
                      ref.read(exchangeScopeProvider).connectionId,
                ),
            onRetry: _refreshCurrentRead,
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
                      backendFeaturesEnabled,
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
            if (backendFeaturesEnabled)
              const TradeAccountControls(showCloseAll: false),
            Expanded(child: orderList),
          ],
        );
      }
      final scope = ref.watch(exchangeScopeProvider);
      if (scope.exchange == ExchangeId.binance) {
        final coverage = ref.watch(binanceHistorySymbolsProvider(scope));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                coverage.when(
                  data: (symbols) => symbols.isEmpty
                      ? 'Chưa có cặp giao dịch để xem lịch sử.'
                      : 'Lịch sử của: ${symbols.join(', ')}',
                  loading: () => 'Đang tải phạm vi lịch sử',
                  error: (_, __) => 'Không thể xác định phạm vi lịch sử.',
                ),
              ),
            ),
            Expanded(child: orderList),
          ],
        );
      }
      return orderList;
    }
  }

  Widget _scrollableState(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );

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
    ExchangePosition position,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
  ) {
    final palette = AppPalette.forBrightness(isDark);
    final posSide = (position.side ?? '').toUpperCase();
    final isLong = posSide == 'LONG';

    final sideColor = posSide == 'NET'
        ? palette.ink
        : (isLong ? palette.positive : palette.negative);
    final sideText = posSide == 'NET' ? 'VỊ THẾ' : (isLong ? 'LONG' : 'SHORT');

    final pnl = double.tryParse((position.unrealizedPnl ?? ''));
    final pnlColor = resolvePnlColor(pnl, palette, hidden: isBalanceHidden);
    final pnlSign = pnl == null ? '' : (pnl >= 0 ? '+' : '');
    final pnlFormatted = pnl == null
        ? '--'
        : NumberFormat("#,##0.00", "en_US").format(pnl.abs());

    final pnlRatio = double.tryParse((position.unrealizedPnlRatio ?? ''));
    final pnlRatioPercent = pnlRatio == null
        ? '--'
        : '${pnlRatio >= 0 ? '+' : ''}${(pnlRatio * 100).toStringAsFixed(2)}%';
    final pnlRatioColor = resolvePnlColor(
      pnlRatio == null ? null : pnlRatio * 100,
      palette,
      hidden: isBalanceHidden,
    );

    final baseCoin = _instrumentBase(position.key);
    final instrumentLabel = _instrumentLabel(position.key);
    final instrumentType =
        position.key.exchange == ExchangeId.binance &&
            position.productLabel.toUpperCase() == 'SWAP'
        ? 'USDⓈ-M'
        : position.productLabel.toUpperCase();

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
                              (position.leverage ?? '').isEmpty
                                  ? '--'
                                  : '${(position.leverage ?? '')}x',
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
            if (position.productLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    '${(position.direction ?? '').toUpperCase()} · ${position.size ?? ''}',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                  Text(
                    '${position.key.exchange == ExchangeId.binance && position.productLabel.toUpperCase() == 'SWAP' ? 'USDⓈ-M' : position.productLabel} · ${(position.marginMode ?? '').toUpperCase()}',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                  if ((position.marginCurrency ?? '').isNotEmpty)
                    Text(
                      'Ký quỹ ${(position.marginCurrency ?? '')}',
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
                        formatAdaptiveNumber((position.entry ?? '')),
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
                        formatAdaptiveNumber((position.mark ?? '')),
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
                        (position.liquidation ?? '').isEmpty
                            ? '--'
                            : formatAdaptiveNumber(
                                (position.liquidation ?? ''),
                              ),
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

  String _nativePositionDisplayKey(ExchangePosition position) {
    if ((position.positionId ?? '').isNotEmpty) {
      return 'native-pos:${(position.positionId ?? '')}';
    }
    return jsonEncode([
      position.key.nativeId,
      position.productLabel,
      (position.side ?? ''),
      (position.marginMode ?? ''),
      (position.marginCurrency ?? ''),
      (position.positionCurrency ?? ''),
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
    ExchangeOrder order,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
    String timeZoneId,
    bool backendFeaturesEnabled,
  ) {
    final palette = AppPalette.forBrightness(isDark);
    final isBuy = (order.side ?? '').toLowerCase() == 'buy';
    final sideColor = isBuy ? palette.positive : palette.negative;
    final sideText = isBuy ? 'MUA' : 'BÁN';
    final timeString = formatOrderTimestamp(
      (order.createdAtMs ?? ''),
      timeZoneId,
    );
    final baseCoin = _instrumentBase(order.key);
    final instrumentLabel = _instrumentLabel(order.key);
    final cardColor = palette.raised;
    final borderColor = palette.border;
    final textColor = palette.ink;
    final subtitleColor = palette.muted;
    final iconBgColor = palette.surface;
    final notional = resolveOrderNotional(order);
    final leverage =
        (order.leverage ?? '').isNotEmpty && (order.leverage ?? '') != '0'
        ? (order.leverage ?? '')
        : null;
    final instrumentType =
        order.key.exchange == ExchangeId.binance &&
            order.productLabel.toUpperCase() == 'SWAP'
        ? 'USDⓈ-M'
        : order.productLabel.toUpperCase();

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
                (order.state ?? '').toUpperCase(),
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
                formatAdaptiveNumber((order.price ?? '')),
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
                formatAdaptiveNumber((order.quantity ?? '')),
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
            if (backendFeaturesEnabled &&
                order.native is OkxOrder &&
                isActiveLimitOrder(order.native as OkxOrder))
              OrderCancellationControl(order: order.native as OkxOrder),
          ],
        ),
      ),
    );
  }

  // --- Thẻ hiển thị LỆNH ---
  Widget _buildOrderCard(
    ExchangeOrder order,
    OrderTab currentTab,
    bool isDark,
    String currency,
    double exchangeRate,
    bool isBalanceHidden,
    String timeZoneId,
    bool backendFeaturesEnabled,
  ) {
    if (currentTab == OrderTab.pending) {
      return _buildPendingOrderCard(
        order,
        isDark,
        currency,
        exchangeRate,
        isBalanceHidden,
        timeZoneId,
        backendFeaturesEnabled,
      );
    }

    final palette = AppPalette.forBrightness(isDark);
    final isBuy = (order.side ?? '').toLowerCase() == 'buy';
    final sideColor = isBuy ? palette.positive : palette.negative;
    final sideText = isBuy ? 'MUA' : 'BÁN';

    final timeString = formatOrderTimestamp(
      (order.createdAtMs ?? ''),
      timeZoneId,
    );

    final baseCoin = _instrumentBase(order.key);
    final instrumentLabel = _instrumentLabel(order.key);
    final instrumentType =
        order.key.exchange == ExchangeId.binance &&
            order.productLabel.toUpperCase() == 'SWAP'
        ? 'USDⓈ-M'
        : order.productLabel.toUpperCase();
    final leverage =
        (order.leverage ?? '').isNotEmpty && (order.leverage ?? '') != '0'
        ? (order.leverage ?? '')
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
                      (order.state ?? '').toUpperCase(),
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
                      'Giá: ${formatAdaptiveNumber((order.price ?? ''))}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space1),
                    Text(
                      'KL: ${formatAdaptiveNumber((order.quantity ?? ''))}',
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
            if (backendFeaturesEnabled &&
                currentTab == OrderTab.pending &&
                order.native is OkxOrder &&
                isActiveLimitOrder(order.native as OkxOrder))
              OrderCancellationControl(order: order.native as OkxOrder),
          ],
        ),
      ),
    );
  }
}
