// File Name: portfolio_screen.dart
// File Path: lib/features/portfolio/presentation/portfolio_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/currency/currency_display_mode.dart';
import '../../../core/widgets/crypto_icon.dart';
import 'providers/portfolio_provider.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../market/presentation/providers/market_provider.dart';
import '../../../core/network/okx_websocket_service.dart';
import '../data/okx_balance_model.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../market/presentation/market_screen.dart';
import '../../fractal_tracker/presentation/fractal_screen.dart';
import '../../pnl_history/presentation/pnl_input_sheet.dart';
import '../../pnl_history/presentation/pnl_history_screen.dart'; // THÊM IMPORT NÀY
import 'widgets/portfolio_currency_amount.dart';

final hideBalanceProvider = StateProvider<bool>((ref) => false);

final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  if (mode == ThemeMode.dark) return true;
  if (mode == ThemeMode.light) return false;
  return SchedulerBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;
});

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  bool _isWsSubscribed = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Tự động làm mới dữ liệu Portfolio mỗi 2 giây ngầm
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ref.invalidate(portfolioFutureProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portfolioAsyncValue = ref.watch(portfolioFutureProvider);
    final livePrices = ref.watch(livePriceProvider);

    final isBalanceHidden = ref.watch(hideBalanceProvider);
    final isDark = ref.watch(isDarkModeProvider);
    final currency = ref.watch(currencyProvider);

    final exchangeRateAsync = ref.watch(vndExchangeRateProvider);
    final exchangeRate = exchangeRateAsync.value ?? 25400.0;

    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.insights, size: 22),
          tooltip: 'Thị trường',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MarketScreen()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.donut_small_outlined, size: 22),
            tooltip: 'BMAG Matrix',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FractalScreen()),
              );
            },
          ),
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
          IconButton(
            icon: const Icon(
              Icons.history_edu,
              size: 22,
            ), // NÚT XEM NHẬT KÝ MỚI
            tooltip: 'Nhật ký PnL',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PnlHistoryScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long, size: 22),
            tooltip: 'Quản lý Lệnh',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const OrdersScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: 'Cài đặt API',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: isDark ? Colors.black : Colors.white,
        backgroundColor: isDark ? Colors.white : Colors.black,
        onRefresh: () async {
          _isWsSubscribed = false;
          ref.invalidate(vndExchangeRateProvider);
          return ref.invalidate(portfolioFutureProvider);
        },
        child: portfolioAsyncValue.when(
          skipLoadingOnReload: true,
          loading: () =>
              Center(child: CircularProgressIndicator(color: textColor)),
          error: (error, stack) =>
              _buildErrorState(context, error.toString(), isDark),
          data: (data) {
            // Đăng ký WebSocket khi load xong danh sách coin
            if (!_isWsSubscribed && data.details.isNotEmpty) {
              _isWsSubscribed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final coins = data.details.map((e) => e.ccy).toList();
                ref.read(okxWebsocketProvider).subscribeToTickers(coins);
              });
            }
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
      // THÊM NÚT NỔI (FAB) ĐỂ MỞ FORM NHẬP LÃI/LỖ FIREBASE
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showPnlInputSheet(context, isDark);
        },
        backgroundColor: isDark ? Colors.white : Colors.black,
        foregroundColor: isDark ? Colors.black : Colors.white,
        icon: const Icon(Icons.add_chart),
        label: const Text(
          'Ghi PnL',
          style: TextStyle(fontWeight: FontWeight.bold),
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

    final pnlColor = totalUnrealizedPnl >= 0 ? Colors.green : Colors.redAccent;
    final pnlSign = totalUnrealizedPnl >= 0 ? '+' : '';

    final textColor = isDark ? Colors.white : Colors.black;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final iconBgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;
    final topCardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // THẺ TỔNG TÀI SẢN
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          width: double.infinity,
          decoration: BoxDecoration(
            color: topCardBgColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
            ],
            border: isDark ? Border.all(color: Colors.grey.shade800) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Tổng tài sản (${CurrencyDisplayMode.labelFor(currency)})',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              PortfolioCurrencyAmount(
                usdtAmount: dynamicTotalEquity,
                currencyMode: currency,
                vndRate: exchangeRate,
                hidden: isHidden,
                crossAxisAlignment: CrossAxisAlignment.center,
                textAlign: TextAlign.center,
                primaryStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                secondaryStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              PortfolioCurrencyAmount(
                usdtAmount: baseEquity,
                currencyMode: currency,
                vndRate: exchangeRate,
                hidden: isHidden,
                primaryPrefix: 'Vốn gốc: ',
                crossAxisAlignment: CrossAxisAlignment.center,
                textAlign: TextAlign.center,
                primaryStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                secondaryStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black45 : Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      totalUnrealizedPnl >= 0
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: isHidden ? Colors.grey : pnlColor,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    PortfolioCurrencyAmount(
                      usdtAmount: totalUnrealizedPnl,
                      currencyMode: currency,
                      vndRate: exchangeRate,
                      hidden: isHidden,
                      showPositiveSign: true,
                      primaryStyle: TextStyle(
                        color: isHidden ? Colors.grey : pnlColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      secondaryStyle: TextStyle(
                        color: isHidden ? Colors.grey : pnlColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _obfuscate(
                        '($pnlSign${pnlRatio.toStringAsFixed(2)}%)',
                        isHidden,
                      ),
                      style: TextStyle(
                        color: isHidden ? Colors.grey : pnlColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Tài sản chi tiết',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.grey.shade800,
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
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: borderColor, width: 1.2),
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
                                fontSize: 11,
                              ),
                            ),
                            if (realtimePriceStr != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '\$$realtimePriceStr',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade800,
                                  fontSize: 11,
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
                            fontSize: 10,
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

  Widget _buildErrorState(
    BuildContext context,
    String errorMessage,
    bool isDark,
  ) {
    return Center(
      child: Text(
        'Lỗi kết nối: $errorMessage',
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
      ),
    );
  }
}
