// File Name: market_screen.dart
// File Path: lib/features/market/presentation/market_screen.dart
// Note: Màn hình hiển thị Top 50 các đồng coin giao dịch SPOT có Volume lớn nhất

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Lấy trạng thái Dark Mode
import '../../market/presentation/providers/market_provider.dart';
import '../../../core/network/okx_websocket_service.dart';

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
      vol24h: double.tryParse(json['volCcy24h'] ?? '0') ?? 0, // Volume quy ra USD
    );
  }

  // Công thức tính % biến động 24h
  double get changePercent => open24h > 0 ? ((last - open24h) / open24h) * 100 : 0.0;
  String get coinSymbol => instId.split('-').first;
}

// --- Provider lấy dữ liệu từ API Public của OKX ---
final marketListProvider = FutureProvider.autoDispose<List<MarketTicker>>((ref) async {
  final dio = ref.watch(dioProvider);

  // Gọi API Public (Không cần truyền 'requiresAuth: true')
  final response = await dio.get('/api/v5/market/tickers', queryParameters: {'instType': 'SPOT'});

  if (response.data['code'] == '0') {
    final List<dynamic> data = response.data['data'];
    final tickers = data
        .where((json) => (json['instId'] as String).endsWith('-USDT')) // Chỉ lấy cặp USDT
        .map((json) => MarketTicker.fromJson(json))
        .where((t) => t.vol24h > 5000000) // Lọc các coin thanh khoản cao (Volume > 5 triệu USD)
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
  bool _isWsSubscribed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(isDarkModeProvider);
    final marketAsync = ref.watch(marketListProvider);

    // Thêm theo dõi giá realtime từ WebSocket
    final livePrices = ref.watch(livePriceProvider);

    // Bảng màu
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final iconBgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text('Thị trường (Top 50)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [],
      ),
      body: RefreshIndicator(
        color: isDark ? Colors.black : Colors.black,
        backgroundColor: isDark ? Colors.white : Colors.white,
        onRefresh: () async {
          _isWsSubscribed = false; // Reset trạng thái để đăng ký lại WS
          return ref.invalidate(marketListProvider);
        },
        child: marketAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: textColor)),
          error: (err, stack) => Center(
            child: Text('Lỗi tải dữ liệu:\n$err', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.redAccent : Colors.red)),
          ),
          data: (tickers) {
            // Đăng ký WebSocket cho Top 50 coin vừa tải về
            if (!_isWsSubscribed && tickers.isNotEmpty) {
              _isWsSubscribed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final coins = tickers.map((e) => e.coinSymbol).toList();
                ref.read(okxWebsocketProvider).subscribeToTickers(coins);
              });
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: tickers.length,
              itemBuilder: (context, index) {
                final t = tickers[index];

                // --- Cập nhật giá Realtime từ WebSocket ---
                double currentPrice = t.last;
                final String? realtimePriceStr = livePrices[t.coinSymbol];
                if (realtimePriceStr != null) {
                  currentPrice = double.tryParse(realtimePriceStr) ?? t.last;
                }

                // Tính toán lại % biến động dựa trên giá Live mới nhất
                final double currentChangePercent = t.open24h > 0
                    ? ((currentPrice - t.open24h) / t.open24h) * 100
                    : 0.0;

                final isPositive = currentChangePercent >= 0;
                final changeColor = isPositive ? Colors.green : Colors.redAccent;
                final changeSign = isPositive ? '+' : '';
                final volFormatted = '\$${(t.vol24h / 1000000).toStringAsFixed(2)}M';

                // Thông minh hiển thị giá: Nếu coin rác (< $1) thì hiện nhiều số thập phân
                String priceFormatted;
                if (currentPrice < 1) {
                  priceFormatted = NumberFormat("#,##0.00####", "en_US").format(currentPrice);
                } else {
                  priceFormatted = NumberFormat("#,##0.00", "en_US").format(currentPrice);
                }

                return Card(
                  elevation: 0,
                  color: cardColor,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: borderColor, width: 1.2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        // Cột 1: Logo và Tên Coin
                        CryptoIcon(
                          symbol: t.coinSymbol,
                          size: 36,
                          backgroundColor: iconBgColor,
                          textColor: textColor,
                          textSize: 14,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.coinSymbol, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                              const SizedBox(height: 4),
                              Text('Vol 24h: $volFormatted', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 11)),
                            ],
                          ),
                        ),

                        // Cột 2: Giá và Khối % Biến động
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('\$$priceFormatted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: changeColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$changeSign${currentChangePercent.toStringAsFixed(2)}%',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
