// File Name: market_provider.dart
// File Path: lib/features/market/presentation/providers/market_provider.dart
// Note: Quản lý state giá realtime dưới dạng Map. VD: {'BTC': '65000.5', 'ETH': '3500.2'}

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/okx_websocket_service.dart';

class LivePriceNotifier extends StateNotifier<Map<String, String>> {
  LivePriceNotifier() : super({});

  void updatePrice(String coin, String price) {
    // Chỉ cập nhật state nếu giá trị thực sự thay đổi để tránh rebuild UI quá nhiều
    if (state[coin] != price) {
      state = {...state, coin: price};
    }
  }

  void replacePrices(Map<String, String> prices) {
    if (state.length == prices.length &&
        state.entries.every((entry) => prices[entry.key] == entry.value)) {
      return;
    }
    state = Map<String, String>.unmodifiable(prices);
  }
}

/// Provider này sẽ được UI lắng nghe để lấy giá Real-time
final livePriceProvider =
    StateNotifierProvider.autoDispose<LivePriceNotifier, Map<String, String>>((
      ref,
    ) {
      final notifier = LivePriceNotifier();
      final wsService = ref.watch(okxWebsocketProvider);

      final subscription = wsService.stream.listen((snapshot) {
        if (snapshot is Map<String, String>) notifier.replacePrices(snapshot);
      });
      ref.onDispose(() => unawaited(subscription.cancel()));

      return notifier;
    });
