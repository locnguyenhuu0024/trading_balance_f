// File Name: market_provider.dart
// File Path: lib/features/market/presentation/providers/market_provider.dart
// Note: Quản lý state giá realtime dưới dạng Map. VD: {'BTC': '65000.5', 'ETH': '3500.2'}

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/okx_websocket_service.dart';
import '../../data/okx_ticker_model.dart';

class LivePriceNotifier extends StateNotifier<Map<String, String>> {
  LivePriceNotifier() : super({});

  void updatePrice(String coin, String price) {
    // Chỉ cập nhật state nếu giá trị thực sự thay đổi để tránh rebuild UI quá nhiều
    if (state[coin] != price) {
      state = {
        ...state,
        coin: price,
      };
    }
  }
}

/// Provider này sẽ được UI lắng nghe để lấy giá Real-time
final livePriceProvider = StateNotifierProvider<LivePriceNotifier, Map<String, String>>((ref) {
  final notifier = LivePriceNotifier();
  final wsService = ref.watch(okxWebsocketProvider);

  // Mở kết nối WebSocket ngay khi provider này được gọi
  wsService.connect();

  // Lắng nghe luồng dữ liệu liên tục từ WebSocket
  wsService.stream.listen((message) {
    try {
      final data = jsonDecode(message);
      // OKX trả về data mảng nếu là channel tickers
      if (data['data'] != null && data['data'] is List) {
        for (var item in data['data']) {
          final ticker = OkxTickerModel.fromJson(item);
          final instId = ticker.instId; // Dạng "BTC-USDT"
          final coin = instId.split('-').first; // Cắt lấy "BTC"

          notifier.updatePrice(coin, ticker.last);
        }
      }
    } catch (e) {
      // Bỏ qua lỗi parse nếu bản tin không phải là JSON giá (VD: event báo subscribe thành công)
    }
  });

  return notifier;
});