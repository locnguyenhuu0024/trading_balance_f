// File Name: okx_ticker_model.dart
// File Path: lib/features/market/data/okx_ticker_model.dart
// Note: Model parse dữ liệu giá realtime từ WebSocket (Public API)

import 'package:freezed_annotation/freezed_annotation.dart';

part 'okx_ticker_model.freezed.dart';
part 'okx_ticker_model.g.dart';

@freezed
class OkxTickerModel with _$OkxTickerModel {
  const factory OkxTickerModel({
    @Default('') String instId, // Cặp giao dịch (VD: BTC-USDT)
    @Default('0') String last,  // Giá khớp gần nhất (Real-time price)
  }) = _OkxTickerModel;

  factory OkxTickerModel.fromJson(Map<String, dynamic> json) =>
      _$OkxTickerModelFromJson(json);
}