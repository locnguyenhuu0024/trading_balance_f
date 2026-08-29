// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'okx_order_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OkxOrderResponseImpl _$$OkxOrderResponseImplFromJson(
  Map<String, dynamic> json,
) => _$OkxOrderResponseImpl(
  code: json['code'] as String? ?? '0',
  msg: json['msg'] as String? ?? '',
  data:
      (json['data'] as List<dynamic>?)
          ?.map((e) => OkxOrder.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$$OkxOrderResponseImplToJson(
  _$OkxOrderResponseImpl instance,
) => <String, dynamic>{
  'code': instance.code,
  'msg': instance.msg,
  'data': instance.data,
};

_$OkxOrderImpl _$$OkxOrderImplFromJson(Map<String, dynamic> json) =>
    _$OkxOrderImpl(
      instId: json['instId'] as String? ?? '',
      instType: json['instType'] as String? ?? '',
      side: json['side'] as String? ?? '',
      px: json['px'] as String? ?? '',
      sz: json['sz'] as String? ?? '',
      notionalUsd: json['notionalUsd'] as String? ?? '',
      fillNotionalUsd: json['fillNotionalUsd'] as String? ?? '',
      avgPx: json['avgPx'] as String? ?? '',
      accFillSz: json['accFillSz'] as String? ?? '',
      tradeQuoteCcy: json['tradeQuoteCcy'] as String? ?? '',
      state: json['state'] as String? ?? '',
      lever: json['lever'] as String? ?? '',
      cTime: json['cTime'] as String? ?? '',
      pnl: json['pnl'] as String? ?? '',
    );

Map<String, dynamic> _$$OkxOrderImplToJson(_$OkxOrderImpl instance) =>
    <String, dynamic>{
      'instId': instance.instId,
      'instType': instance.instType,
      'side': instance.side,
      'px': instance.px,
      'sz': instance.sz,
      'notionalUsd': instance.notionalUsd,
      'fillNotionalUsd': instance.fillNotionalUsd,
      'avgPx': instance.avgPx,
      'accFillSz': instance.accFillSz,
      'tradeQuoteCcy': instance.tradeQuoteCcy,
      'state': instance.state,
      'lever': instance.lever,
      'cTime': instance.cTime,
      'pnl': instance.pnl,
    };
