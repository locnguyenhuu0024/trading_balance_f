// File Name: portfolio_screen.dart
// File Path: lib/features/portfolio/presentation/portfolio_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/currency/currency_display_mode.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/platform_brightness_provider.dart';
import '../../../core/theme/pnl_color.dart';
import '../../../core/widgets/crypto_icon.dart';
import 'providers/portfolio_provider.dart';
import '../../orders/presentation/providers/trade_session_provider.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../market/presentation/providers/market_provider.dart';
import '../../../core/network/okx_websocket_service.dart';
import '../data/okx_balance_model.dart';
import 'widgets/portfolio_currency_amount.dart';

final hideBalanceProvider = StateProvider<bool>((ref) => false);

final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  if (mode == ThemeMode.dark) return true;
  if (mode == ThemeMode.light) return false;
  return ref.watch(
    platformBrightnessProvider.select((observer) => observer.isDark),
  );
});

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  bool _portfolioRefreshInFlight = false;
  bool _tickerSubscriptionScheduled = false;
  List<String> _subscribedCoins = const <String>[];
  List<String>? _pendingCoins;
  OkxWebsocketService? _tickerService;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshPortfolio(automatic: true));
    });
  }

  Future<void> _refreshPortfolio({bool automatic = false}) async {
    final tradeState = ref.read(tradeSessionProvider);
    final currentRead = ref.read(portfolioFutureProvider);
    if (!mounted ||
        tradeState.isLoading ||
        !tradeState.isAuthenticated ||
        _portfolioRefreshInFlight ||
        currentRead.isLoading ||
        (automatic &&
            isTerminalForegroundReadFailure(currentRead.asError?.error))) {
      return;
    }
    _portfolioRefreshInFlight = true;
    ref.invalidate(portfolioFutureProvider);
    try {
      await ref.read(portfolioFutureProvider.future);
    } catch (_) {
      // The watched provider renders refresh errors in the screen.
    } finally {
      if (mounted) _portfolioRefreshInFlight = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickerService?.clearLegacySubscription();
    super.dispose();
  }

  void _syncTickerSubscription(List<String> coins) {
    final nextCoins = List<String>.unmodifiable(coins);
    if (_pendingCoins != null && _sameCoins(_pendingCoins!, nextCoins)) return;
    if (_pendingCoins == null && _sameCoins(_subscribedCoins, nextCoins))
      return;
    _pendingCoins = nextCoins;
    if (_tickerSubscriptionScheduled) return;
    _tickerSubscriptionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickerSubscriptionScheduled = false;
      if (!mounted) return;
      final requestedCoins = _pendingCoins ?? const <String>[];
      _pendingCoins = null;
      if (_sameCoins(_subscribedCoins, requestedCoins)) return;
      _subscribedCoins = requestedCoins;
      final service = ref.read(okxWebsocketProvider);
      _tickerService = service;
      if (requestedCoins.isEmpty) {
        service.clearLegacySubscription();
      } else {
        service.subscribeToTickers(requestedCoins);
      }
    });
  }

  bool _sameCoins(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final portfolioAsyncValue = ref.watch(portfolioFutureProvider);
    final isSessionLoading = ref.watch(
      tradeSessionProvider.select((state) => state.isLoading),
    );
    final livePrices = ref.watch(livePriceProvider);

    final isBalanceHidden = ref.watch(hideBalanceProvider);
    final isDark = ref.watch(isDarkModeProvider);
    final currency = ref.watch(currencyProvider);

    final exchangeRateAsync = ref.watch(vndExchangeRateProvider);
    final exchangeRate = exchangeRateAsync.value ?? 25400.0;

    final palette = AppPalette.of(context);
    final bgColor = palette.background;
    final textColor = palette.ink;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              isBalanceHidden ? Icons.visibility_off : Icons.visibility,
              size: 22,
            ),
            tooltip: isBalanceHidden ? 'Hiện số dư' : 'Ẩn số dư',
            onPressed: () {
              ref.read(hideBalanceProvider.notifier).state = !isBalanceHidden;
            },
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: RefreshIndicator(
          color: palette.ink,
          backgroundColor: palette.raised,
          onRefresh: () async {
            ref.invalidate(vndExchangeRateProvider);
            await _refreshPortfolio();
          },
          child:
              !portfolioAsyncValue.hasValue &&
                  (isSessionLoading || portfolioAsyncValue.isLoading)
              ? Center(child: CircularProgressIndicator(color: textColor))
              : portfolioAsyncValue.when(
                  skipLoadingOnReload: false,
                  loading: () => Center(
                    child: CircularProgressIndicator(color: textColor),
                  ),
                  error: (error, stack) {
                    _syncTickerSubscription(const <String>[]);
                    return _buildErrorState(context, error.toString(), isDark);
                  },
                  data: (data) {
                    _syncTickerSubscription(
                      data.details.map((e) => e.ccy).toList(),
                    );
                    return _buildPortfolioData(
                      data,
                      livePrices,
                      isBalanceHidden,
                      isDark,
                      currency,
                      exchangeRate,
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _obfuscate(String value, bool isHidden) {
    return isHidden ? '******' : value;
  }

  Widget _buildPortfolioData(
    OkxAccountData accountData,
    Map<String, String> livePrices,
    bool isHidden,
    bool isDark,
    String currency,
    double exchangeRate,
  ) {
    double dynamicTotalEquity = 0.0;
    double totalUnrealizedPnl = 0.0;

    for (var coin in accountData.details) {
      final double eq = double.tryParse(coin.eq) ?? 0.0;
      final double totalCoinUpl = double.tryParse(coin.upl) ?? 0.0;

      final String? realtimePriceStr = livePrices[coin.ccy];
      double priceToUsd = 0.0;

      if (realtimePriceStr != null) {
        priceToUsd = double.tryParse(realtimePriceStr) ?? 0.0;
      } else {
        final double eqUsd = double.tryParse(coin.eqUsd) ?? 0.0;
        if (eq > 0) {
          priceToUsd = eqUsd / eq;
        }
      }

      dynamicTotalEquity += eq * priceToUsd;
      totalUnrealizedPnl += totalCoinUpl * priceToUsd;
    }

    final double baseEquity = dynamicTotalEquity - totalUnrealizedPnl;
    final double pnlRatio = baseEquity > 0
        ? (totalUnrealizedPnl / baseEquity) * 100
        : 0.0;

    final palette = AppPalette.forBrightness(isDark);
    final textColor = palette.ink;
    final cardColor = palette.raised;
    final borderColor = palette.border;
    final subtitleColor = palette.muted;
    final iconBgColor = palette.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAssetSummary(
          totalEquity: dynamicTotalEquity,
          baseEquity: baseEquity,
          unrealizedPnl: totalUnrealizedPnl,
          pnlRatio: pnlRatio,
          isHidden: isHidden,
          isDark: isDark,
          currency: currency,
          exchangeRate: exchangeRate,
        ),

        Divider(height: 1, indent: 16, endIndent: 16, color: palette.border),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Tài sản chi tiết',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),

        // DANH SÁCH COIN
        Expanded(
          child: accountData.details.isEmpty
              ? Center(
                  child: Text(
                    'Không có tài sản nào.',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: accountData.details.length,
                  itemBuilder: (context, index) {
                    final coin = accountData.details[index];
                    final double eq = double.tryParse(coin.eq) ?? 0.0;
                    final String? realtimePriceStr = livePrices[coin.ccy];

                    double currentUsdValue = 0.0;
                    if (realtimePriceStr != null) {
                      currentUsdValue =
                          eq * (double.tryParse(realtimePriceStr) ?? 0.0);
                    } else {
                      currentUsdValue = double.tryParse(coin.eqUsd) ?? 0.0;
                    }

                    // Ẩn các loại coin có giá trị nhỏ hơn $0.01 (dust)
                    if (currentUsdValue < 0.01) return const SizedBox.shrink();

                    return Card(
                      elevation: 0,
                      color: cardColor,
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusMedium,
                        ),
                        side: BorderSide(color: borderColor),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        leading: CryptoIcon(
                          symbol: coin.ccy,
                          size: 34,
                          backgroundColor: iconBgColor,
                          textColor: textColor,
                          textSize: 14,
                        ),
                        title: Text(
                          coin.ccy,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              _obfuscate(
                                'SL: ${NumberFormat("#,##0.00##", "en_US").format(eq)}',
                                isHidden,
                              ),
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 12,
                              ),
                            ),
                            if (realtimePriceStr != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '\$$realtimePriceStr',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: PortfolioCurrencyAmount(
                          usdtAmount: currentUsdValue,
                          currencyMode: currency,
                          vndRate: exchangeRate,
                          hidden: isHidden,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          textAlign: TextAlign.right,
                          primaryStyle: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: textColor,
                          ),
                          secondaryStyle: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: subtitleColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAssetSummary({
    required double totalEquity,
    required double baseEquity,
    required double unrealizedPnl,
    required double pnlRatio,
    required bool isHidden,
    required bool isDark,
    required String currency,
    required double exchangeRate,
  }) {
    final palette = AppPalette.forBrightness(isDark);
    final textColor = palette.ink;
    final labelColor = palette.muted;
    final pnlColor = resolvePnlColor(unrealizedPnl, palette, hidden: isHidden);
    final pnlRatioColor = resolvePnlColor(pnlRatio, palette, hidden: isHidden);
    final pnlSign = unrealizedPnl >= 0 ? '+' : '';

    final totalBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tổng tài sản (${CurrencyDisplayMode.labelFor(currency)})',
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: PortfolioCurrencyAmount(
            usdtAmount: totalEquity,
            currencyMode: currency,
            vndRate: exchangeRate,
            hidden: isHidden,
            primaryStyle: TextStyle(
              color: textColor,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            secondaryStyle: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    final capitalBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vốn gốc',
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        PortfolioCurrencyAmount(
          usdtAmount: baseEquity,
          currencyMode: currency,
          vndRate: exchangeRate,
          hidden: isHidden,
          primaryStyle: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          secondaryStyle: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    final pnlBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lãi / lỗ chưa thực hiện',
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              pnlColor == palette.muted
                  ? Icons.remove_rounded
                  : unrealizedPnl > 0
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: pnlColor,
              size: 14,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: PortfolioCurrencyAmount(
                usdtAmount: unrealizedPnl,
                currencyMode: currency,
                vndRate: exchangeRate,
                hidden: isHidden,
                showPositiveSign: true,
                primaryStyle: TextStyle(
                  color: pnlColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                secondaryStyle: TextStyle(
                  color: pnlColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _obfuscate('($pnlSign${pnlRatio.toStringAsFixed(2)}%)', isHidden),
          style: TextStyle(
            color: pnlRatioColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return Padding(
      key: const Key('portfolio-asset-summary'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 640) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 2, child: totalBlock),
                Container(
                  width: 1,
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: palette.border,
                ),
                Expanded(child: capitalBlock),
                const SizedBox(width: 20),
                Expanded(child: pnlBlock),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              totalBlock,
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: capitalBlock),
                  const SizedBox(width: 16),
                  Expanded(child: pnlBlock),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    String errorMessage,
    bool isDark,
  ) {
    return Center(
      child: Text(
        'Lỗi kết nối: $errorMessage',
        style: TextStyle(color: AppPalette.of(context).ink),
      ),
    );
  }
}
