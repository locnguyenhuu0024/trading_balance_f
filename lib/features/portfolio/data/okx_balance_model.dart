// File Name: okx_balance_model.dart
// File Path: lib/features/portfolio/data/okx_balance_model.dart

import 'package:freezed_annotation/freezed_annotation.dart';

part 'okx_balance_model.freezed.dart';
part 'okx_balance_model.g.dart';

@freezed
class OkxBalanceResponse with _$OkxBalanceResponse {
  const factory OkxBalanceResponse({
    @Default('0') String code,
    @Default('') String msg,
    @Default([]) List<OkxAccountData> data,
  }) = _OkxBalanceResponse;

  factory OkxBalanceResponse.fromJson(Map<String, dynamic> json) =>
      _$OkxBalanceResponseFromJson(json);
}

@freezed
class OkxAccountData with _$OkxAccountData {
  const factory OkxAccountData({
    @Default('0') String totalEq,
    @Default('0') String imr,   // Ký quỹ Cross Margin tổng
    @Default('0') String isoEq, // Ký quỹ Isolated Margin tổng
    @Default([]) List<OkxCoinDetail> details,
  }) = _OkxAccountData;

  factory OkxAccountData.fromJson(Map<String, dynamic> json) =>
      _$OkxAccountDataFromJson(json);
}

@freezed
class OkxCoinDetail with _$OkxCoinDetail {
  const factory OkxCoinDetail({
    @Default('') String ccy,
    @Default('0') String cashBal,
    @Default('0') String availBal,  // Tiền dư/khả dụng vật lý (THÊM MỚI)
    @Default('0') String availEq,   // Tiền dư/khả dụng margin (THÊM MỚI)
    @Default('0') String eq,
    @Default('0') String eqUsd,
    @Default('0') String upl,
    @Default('0') String frozenBal,
    @Default('0') String ordFrozen,
    @Default('0') String imr,
    @Default('0') String isoEq,
    @Default('0') String isoUpl,
  }) = _OkxCoinDetail;

  factory OkxCoinDetail.fromJson(Map<String, dynamic> json) =>
      _$OkxCoinDetailFromJson(json);
}