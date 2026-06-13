// File Name: okx_websocket_service.dart
// File Path: lib/core/network/okx_websocket_service.dart
// Note: Quản lý kết nối WebSocket tới sàn OKX (Sử dụng web_socket_channel)

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Provider cung cấp WebSocket Service, tự động ngắt kết nối khi không còn dùng
final okxWebsocketProvider = Provider<OkxWebsocketService>((ref) {
  final service = OkxWebsocketService();
  ref.onDispose(() => service.disconnect());
  return service;
});

class OkxWebsocketService {
  WebSocketChannel? _channel;
  final String _wsUrl = 'wss://ws.okx.com:8443/ws/v5/public';

  // Stream phát dữ liệu raw string từ WS
  Stream<dynamic> get stream => _channel?.stream ?? const Stream.empty();

  void connect() {
    if (_channel != null) return;
    _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
  }

  /// Đăng ký nhận giá realtime cho một danh sách các coin.
  /// Ví dụ truyền vào: ['BTC', 'ETH']
  void subscribeToTickers(List<String> coinSymbols) {
    if (_channel == null) connect();

    // OKX yêu cầu định dạng instId là: "BTC-USDT"
    final args = coinSymbols.map((coin) => {
      "channel": "tickers",
      "instId": "$coin-USDT"
    }).toList();

    final request = {
      "op": "subscribe",
      "args": args
    };

    _channel!.sink.add(jsonEncode(request));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}