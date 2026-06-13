// File Name: okx_order_model.dart
// File Path: lib/features/orders/data/okx_order_model.dart
// Note: Model chứa thông tin của một lệnh trade trên sàn OKX

import 'package:freezed_annotation/freezed_annotation.dart';

part 'okx_order_model.freezed.dart';
part 'okx_order_model.g.dart';

@freezed
class OkxOrderResponse with _$OkxOrderResponse {
  const factory OkxOrderResponse({
    @Default('0') String code,
    @Default('') String msg,
    @Default([]) List<OkxOrder> data,
  }) = _OkxOrderResponse;

  factory OkxOrderResponse.fromJson(Map<String, dynamic> json) =>
      _$OkxOrderResponseFromJson(json);
}

@freezed
class OkxOrder with _$OkxOrder {
  const factory OkxOrder({
    @Default('') String instId,   // Cặp giao dịch (VD: BTC-USDT)
    @Default('') String instType, // Loại (SPOT, MARGIN, SWAP, FUTURES)
    @Default('') String side,     // Chiều giao dịch (buy, sell)
    @Default('') String px,       // Giá đặt lệnh
    @Default('') String sz,       // Kích thước/Số lượng lệnh
    @Default('') String state,    // Trạng thái (live, filled, canceled)
    @Default('') String lever,    // Đòn bẩy (Dành cho margin/futures)
    @Default('') String cTime,    // Thời gian tạo lệnh (Unix Timestamp ms)
    @Default('') String pnl,      // Lãi/Lỗ của lệnh (Nếu có)
  }) = _OkxOrder;

  factory OkxOrder.fromJson(Map<String, dynamic> json) =>
      _$OkxOrderFromJson(json);
}