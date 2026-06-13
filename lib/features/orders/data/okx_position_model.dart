// File Name: okx_position_model.dart
// File Path: lib/features/orders/data/okx_position_model.dart
// Note: Model chứa thông tin của một Vị thế đang mở (Margin, Futures, Swap)

import 'package:freezed_annotation/freezed_annotation.dart';

part 'okx_position_model.freezed.dart';
part 'okx_position_model.g.dart';

@freezed
class OkxPosition with _$OkxPosition {
  const factory OkxPosition({
    @Default('') String instId,   // Cặp giao dịch (VD: BTC-USDT-SWAP)
    @Default('') String posSide,  // Chiều vị thế (long, short, net)
    @Default('') String pos,      // Kích thước vị thế (Số lượng)
    @Default('') String avgPx,    // Giá vào lệnh trung bình (Entry Price)
    @Default('') String markPx,   // Giá đánh dấu hiện hành (Mark Price)
    @Default('') String lever,    // Đòn bẩy hiện tại
    @Default('') String liqPx,    // Giá thanh lý ước tính
    @Default('') String upl,      // Lãi/lỗ chưa thực hiện (Unrealized PnL - USD)
    @Default('') String uplRatio, // Tỷ lệ Lãi/lỗ
    @Default('') String mgnMode,  // Chế độ Margin (cross hoặc isolated)
  }) = _OkxPosition;

  factory OkxPosition.fromJson(Map<String, dynamic> json) =>
      _$OkxPositionFromJson(json);
}