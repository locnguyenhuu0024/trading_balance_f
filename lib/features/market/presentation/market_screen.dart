// File Name: market_screen.dart
// File Path: lib/features/market/presentation/market_screen.dart
// Note: Màn hình hiển thị Top 50 các đồng coin giao dịch SPOT có Volume lớn nhất

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Lấy trạng thái Dark Mode

// --- Model dữ liệu nội bộ cho Market ---
class MarketTicker {
  final String instId;
  final double last;
  final double open24h;
  final double vol24h;

  MarketTicker({
    required this.instId,
    required this.last,
    required this.open24h,
    required this.vol24h,
  });

  factory MarketTicker.fromJson(Map<String, dynamic> json) {
    return MarketTicker(
      instId: json['instId'] ?? '',
      last: double.tryParse(json['last'] ?? '0') ?? 0,
      open24h: double.tryParse(json['sodUtc0'] ?? '0') ?? 0,
      vol24h:
          double.tryParse(json['volCcy24h'] ?? '0') ?? 0, // Volume quy ra USD
    );
  }

  // Công thức tính % biến động 24h
  double get changePercent =>
      open24h > 0 ? ((last - open24h) / open24h) * 100 : 0.0;
  String get coinSymbol => instId.split('-').first;
}

// --- Provider lấy dữ liệu từ API Public của OKX ---
final marketListProvider = FutureProvider.autoDispose<List<MarketTicker>>((
  ref,
) async {
  final client = ref.watch(backendDataClientProvider);

  final response = await client.get(
    '/api/v5/market/tickers',
    queryParameters: {'instType': 'SPOT'},
  );

  if (response.data['code'] == '0') {
    final List<dynamic> data = response.data['data'];
    final tickers = data
        .where(
          (json) => (json['instId'] as String).endsWith('-USDT'),
        ) // Chỉ lấy cặp USDT
        .map((json) => MarketTicker.fromJson(json))
        .where(
          (t) => t.vol24h > 5000000,
        ) // Lọc các coin thanh khoản cao (Volume > 5 triệu USD)
        .toList();

    // Sắp xếp theo volume giảm dần
    tickers.sort((a, b) => b.vol24h.compareTo(a.vol24h));

    return tickers.take(50).toList(); // Lấy Top 50
  } else {
    throw Exception(response.data['msg']);
  }
});

// --- Giao diện hiển thị (Screen) ---
class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  bool _refreshInFlight = false;

  Future<void> _refreshMarket() async {
    if (_refreshInFlight) return;
    setState(() => _refreshInFlight = true);
    try {
      ref.invalidate(marketListProvider);
      await ref.read(marketListProvider.future);
    } catch (_) {
      // The watched provider renders the read error.
    } finally {
      if (mounted) setState(() => _refreshInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(isDarkModeProvider);
    final marketAsync = ref.watch(marketListProvider);

    final palette = AppPalette.forBrightness(isDark);
    final bgColor = palette.background;
    final textColor = palette.ink;
    final cardColor = palette.raised;
    final borderColor = palette.border;
    final iconBgColor = palette.surface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Thị trường (Top 50)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        actions: [
          ManualRefreshButton(
            buttonKey: const Key('market-manual-refresh'),
            onRefresh: _refreshMarket,
            isBusy: _refreshInFlight || marketAsync.isLoading,
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: RefreshIndicator(
          color: palette.ink,
          backgroundColor: palette.raised,
          onRefresh: _refreshMarket,
          child: marketAsync.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: textColor)),
            error: (err, stack) => Center(
              child: Text(
                'Lỗi tải dữ liệu:\n$err',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.negative),
              ),
            ),
            data: (tickers) {
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.space4,
                  vertical: AppTokens.space2,
                ),
                itemCount: tickers.length,
                itemBuilder: (context, index) {
                  final t = tickers[index];
                  final currentPrice = t.last;

                  // Tính toán lại % biến động dựa trên giá Live mới nhất
                  final double currentChangePercent = t.open24h > 0
                      ? ((currentPrice - t.open24h) / t.open24h) * 100
                      : 0.0;

                  final isPositive = currentChangePercent >= 0;
                  final changeColor = isPositive
                      ? palette.positive
                      : palette.negative;
                  final changeSign = isPositive ? '+' : '';
                  final volFormatted =
                      '\$${(t.vol24h / 1000000).toStringAsFixed(2)}M';

                  // Thông minh hiển thị giá: Nếu coin rác (< $1) thì hiện nhiều số thập phân
                  String priceFormatted;
                  if (currentPrice < 1) {
                    priceFormatted = NumberFormat(
                      "#,##0.00####",
                      "en_US",
                    ).format(currentPrice);
                  } else {
                    priceFormatted = NumberFormat(
                      "#,##0.00",
                      "en_US",
                    ).format(currentPrice);
                  }

                  return Card(
                    elevation: 0,
                    color: cardColor,
                    margin: const EdgeInsets.only(bottom: AppTokens.space2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTokens.radiusMedium,
                      ),
                      side: BorderSide(color: borderColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space3,
                        vertical: AppTokens.space3,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final coinIdentity = Row(
                            children: [
                              CryptoIcon(
                                symbol: t.coinSymbol,
                                size: 36,
                                backgroundColor: iconBgColor,
                                textColor: textColor,
                                textSize: 14,
                              ),
                              const SizedBox(width: AppTokens.space3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.coinSymbol,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: AppTokens.space1),
                                    Text(
                                      'Vol 24h: $volFormatted',
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                          final quote = Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$$priceFormatted',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: AppTokens.space2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.space2,
                                  vertical: AppTokens.space1,
                                ),
                                decoration: BoxDecoration(
                                  color: changeColor,
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.radiusSmall,
                                  ),
                                ),
                                child: Text(
                                  '$changeSign${currentChangePercent.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    color: palette.onStrong,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          );

                          if (constraints.maxWidth < 400) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                coinIdentity,
                                const SizedBox(height: AppTokens.space2),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: quote,
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: coinIdentity),
                              const SizedBox(width: AppTokens.space3),
                              quote,
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
