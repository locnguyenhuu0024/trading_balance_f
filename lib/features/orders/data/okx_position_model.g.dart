// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'okx_position_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OkxPositionImpl _$$OkxPositionImplFromJson(Map<String, dynamic> json) =>
    _$OkxPositionImpl(
      instId: json['instId'] as String? ?? '',
      posSide: json['posSide'] as String? ?? '',
      pos: json['pos'] as String? ?? '',
      avgPx: json['avgPx'] as String? ?? '',
      markPx: json['markPx'] as String? ?? '',
      lever: json['lever'] as String? ?? '',
      liqPx: json['liqPx'] as String? ?? '',
      upl: json['upl'] as String? ?? '',
      uplRatio: json['uplRatio'] as String? ?? '',
      mgnMode: json['mgnMode'] as String? ?? '',
      notionalUsd: json['notionalUsd'] as String? ?? '',
      instType: json['instType'] as String? ?? '',
      positionId: json['positionId'] as String? ?? '',
      signedSize: json['signedSize'] as String? ?? '',
      size: json['size'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
      marginCurrency: json['marginCurrency'] as String? ?? '',
      positionCurrency: json['positionCurrency'] as String? ?? '',
      identity:
          json['identity'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
      eligibleActions:
          json['eligibleActions'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );

Map<String, dynamic> _$$OkxPositionImplToJson(_$OkxPositionImpl instance) =>
    <String, dynamic>{
      'instId': instance.instId,
      'posSide': instance.posSide,
      'pos': instance.pos,
      'avgPx': instance.avgPx,
      'markPx': instance.markPx,
      'lever': instance.lever,
      'liqPx': instance.liqPx,
      'upl': instance.upl,
      'uplRatio': instance.uplRatio,
      'mgnMode': instance.mgnMode,
      'notionalUsd': instance.notionalUsd,
      'instType': instance.instType,
      'positionId': instance.positionId,
      'signedSize': instance.signedSize,
      'size': instance.size,
      'direction': instance.direction,
      'marginCurrency': instance.marginCurrency,
      'positionCurrency': instance.positionCurrency,
      'identity': instance.identity,
      'eligibleActions': instance.eligibleActions,
    };
