// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'okx_balance_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OkxBalanceResponseImpl _$$OkxBalanceResponseImplFromJson(
  Map<String, dynamic> json,
) => _$OkxBalanceResponseImpl(
  code: json['code'] as String? ?? '0',
  msg: json['msg'] as String? ?? '',
  data:
      (json['data'] as List<dynamic>?)
          ?.map((e) => OkxAccountData.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$$OkxBalanceResponseImplToJson(
  _$OkxBalanceResponseImpl instance,
) => <String, dynamic>{
  'code': instance.code,
  'msg': instance.msg,
  'data': instance.data,
};

_$OkxAccountDataImpl _$$OkxAccountDataImplFromJson(Map<String, dynamic> json) =>
    _$OkxAccountDataImpl(
      totalEq: json['totalEq'] as String? ?? '0',
      imr: json['imr'] as String? ?? '0',
      isoEq: json['isoEq'] as String? ?? '0',
      details:
          (json['details'] as List<dynamic>?)
              ?.map((e) => OkxCoinDetail.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$OkxAccountDataImplToJson(
  _$OkxAccountDataImpl instance,
) => <String, dynamic>{
  'totalEq': instance.totalEq,
  'imr': instance.imr,
  'isoEq': instance.isoEq,
  'details': instance.details,
};

_$OkxCoinDetailImpl _$$OkxCoinDetailImplFromJson(Map<String, dynamic> json) =>
    _$OkxCoinDetailImpl(
      ccy: json['ccy'] as String? ?? '',
      cashBal: json['cashBal'] as String? ?? '0',
      availBal: json['availBal'] as String? ?? '0',
      availEq: json['availEq'] as String? ?? '0',
      eq: json['eq'] as String? ?? '0',
      eqUsd: json['eqUsd'] as String? ?? '0',
      upl: json['upl'] as String? ?? '0',
      frozenBal: json['frozenBal'] as String? ?? '0',
      ordFrozen: json['ordFrozen'] as String? ?? '0',
      imr: json['imr'] as String? ?? '0',
      isoEq: json['isoEq'] as String? ?? '0',
      isoUpl: json['isoUpl'] as String? ?? '0',
    );

Map<String, dynamic> _$$OkxCoinDetailImplToJson(_$OkxCoinDetailImpl instance) =>
    <String, dynamic>{
      'ccy': instance.ccy,
      'cashBal': instance.cashBal,
      'availBal': instance.availBal,
      'availEq': instance.availEq,
      'eq': instance.eq,
      'eqUsd': instance.eqUsd,
      'upl': instance.upl,
      'frozenBal': instance.frozenBal,
      'ordFrozen': instance.ordFrozen,
      'imr': instance.imr,
      'isoEq': instance.isoEq,
      'isoUpl': instance.isoUpl,
    };
