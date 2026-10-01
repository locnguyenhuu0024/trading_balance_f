// File Name: okx_position_model.dart
// File Path: lib/features/orders/data/okx_position_model.dart
// Note: Model chứa thông tin của một Vị thế đang mở (Margin, Futures, Swap)

import 'package:freezed_annotation/freezed_annotation.dart';

part 'okx_position_model.freezed.dart';
part 'okx_position_model.g.dart';

@freezed
class OkxPosition with _$OkxPosition {
  const factory OkxPosition({
    @Default('') String instId, // Cặp giao dịch (VD: BTC-USDT-SWAP)
    @Default('') String posSide, // Chiều vị thế (long, short, net)
    @Default('') String pos, // Kích thước vị thế (Số lượng)
    @Default('') String avgPx, // Giá vào lệnh trung bình (Entry Price)
    @Default('') String markPx, // Giá đánh dấu hiện hành (Mark Price)
    @Default('') String lever, // Đòn bẩy hiện tại
    @Default('') String liqPx, // Giá thanh lý ước tính
    @Default('') String upl, // Lãi/lỗ chưa thực hiện (Unrealized PnL - USD)
    @Default('') String uplRatio, // Tỷ lệ Lãi/lỗ
    @Default('') String mgnMode, // Chế độ Margin (cross hoặc isolated)
    @Default('') String notionalUsd, // Giá trị danh nghĩa vị thế theo USD
    @Default('') String instType,
    @Default('') String positionId,
    @Default('') String signedSize,
    @Default('') String size,
    @Default('') String direction,
    @Default('') String marginCurrency,
    @Default('') String positionCurrency,
    @Default(<String, dynamic>{}) Map<String, dynamic> identity,
    @Default(<String, dynamic>{}) Map<String, dynamic> eligibleActions,
  }) = _OkxPosition;

  factory OkxPosition.fromJson(Map<String, dynamic> json) =>
      _$OkxPositionFromJson(json);
}

/// Projects the private trade API's account-owned position into the shared
/// position-card model. The action identity and eligibility always come from
/// the backend response, never from the read-only OKX display path.
OkxPosition positionFromTradeJson(Map<String, dynamic> json) {
  return OkxPosition(
    instId: _tradeString(json['instrumentId'] ?? json['instId']),
    posSide: _tradeString(json['positionSide'] ?? json['posSide']),
    pos: _tradeString(json['size'] ?? json['pos']),
    avgPx: _tradeString(json['avgPx']),
    markPx: _tradeString(json['markPx']),
    liqPx: _tradeString(json['liqPx']),
    upl: _tradeString(json['upl']),
    uplRatio: _tradeString(json['uplRatio']),
    notionalUsd: _tradeString(json['notionalUsd']),
    lever: _tradeString(json['lever']),
    mgnMode: _tradeString(json['marginMode'] ?? json['mgnMode']),
    instType: _tradeString(json['instrumentType'] ?? json['instType']),
    positionId: _tradeString(json['positionId']),
    signedSize: _tradeString(json['signedSize']),
    size: _tradeString(json['size']),
    direction: _tradeString(json['direction']),
    marginCurrency: _tradeString(json['marginCurrency']),
    positionCurrency: _tradeString(json['positionCurrency']),
    identity: _tradeMap(json['identity']),
    eligibleActions: _tradeMap(json['eligibleActions']),
  );
}

String _tradeString(dynamic value) => value == null ? '' : value.toString();

Map<String, dynamic> _tradeMap(dynamic value) {
  if (value is! Map) return const <String, dynamic>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}
