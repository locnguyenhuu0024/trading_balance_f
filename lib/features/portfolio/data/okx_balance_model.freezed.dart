// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'okx_balance_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

OkxBalanceResponse _$OkxBalanceResponseFromJson(Map<String, dynamic> json) {
  return _OkxBalanceResponse.fromJson(json);
}

/// @nodoc
mixin _$OkxBalanceResponse {
  String get code => throw _privateConstructorUsedError;
  String get msg => throw _privateConstructorUsedError;
  List<OkxAccountData> get data => throw _privateConstructorUsedError;

  /// Serializes this OkxBalanceResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OkxBalanceResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OkxBalanceResponseCopyWith<OkxBalanceResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OkxBalanceResponseCopyWith<$Res> {
  factory $OkxBalanceResponseCopyWith(
    OkxBalanceResponse value,
    $Res Function(OkxBalanceResponse) then,
  ) = _$OkxBalanceResponseCopyWithImpl<$Res, OkxBalanceResponse>;
  @useResult
  $Res call({String code, String msg, List<OkxAccountData> data});
}

/// @nodoc
class _$OkxBalanceResponseCopyWithImpl<$Res, $Val extends OkxBalanceResponse>
    implements $OkxBalanceResponseCopyWith<$Res> {
  _$OkxBalanceResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OkxBalanceResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? code = null, Object? msg = null, Object? data = null}) {
    return _then(
      _value.copyWith(
            code: null == code
                ? _value.code
                : code // ignore: cast_nullable_to_non_nullable
                      as String,
            msg: null == msg
                ? _value.msg
                : msg // ignore: cast_nullable_to_non_nullable
                      as String,
            data: null == data
                ? _value.data
                : data // ignore: cast_nullable_to_non_nullable
                      as List<OkxAccountData>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OkxBalanceResponseImplCopyWith<$Res>
    implements $OkxBalanceResponseCopyWith<$Res> {
  factory _$$OkxBalanceResponseImplCopyWith(
    _$OkxBalanceResponseImpl value,
    $Res Function(_$OkxBalanceResponseImpl) then,
  ) = __$$OkxBalanceResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String msg, List<OkxAccountData> data});
}

/// @nodoc
class __$$OkxBalanceResponseImplCopyWithImpl<$Res>
    extends _$OkxBalanceResponseCopyWithImpl<$Res, _$OkxBalanceResponseImpl>
    implements _$$OkxBalanceResponseImplCopyWith<$Res> {
  __$$OkxBalanceResponseImplCopyWithImpl(
    _$OkxBalanceResponseImpl _value,
    $Res Function(_$OkxBalanceResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OkxBalanceResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? code = null, Object? msg = null, Object? data = null}) {
    return _then(
      _$OkxBalanceResponseImpl(
        code: null == code
            ? _value.code
            : code // ignore: cast_nullable_to_non_nullable
                  as String,
        msg: null == msg
            ? _value.msg
            : msg // ignore: cast_nullable_to_non_nullable
                  as String,
        data: null == data
            ? _value._data
            : data // ignore: cast_nullable_to_non_nullable
                  as List<OkxAccountData>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OkxBalanceResponseImpl implements _OkxBalanceResponse {
  const _$OkxBalanceResponseImpl({
    this.code = '0',
    this.msg = '',
    final List<OkxAccountData> data = const [],
  }) : _data = data;

  factory _$OkxBalanceResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$OkxBalanceResponseImplFromJson(json);

  @override
  @JsonKey()
  final String code;
  @override
  @JsonKey()
  final String msg;
  final List<OkxAccountData> _data;
  @override
  @JsonKey()
  List<OkxAccountData> get data {
    if (_data is EqualUnmodifiableListView) return _data;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_data);
  }

  @override
  String toString() {
    return 'OkxBalanceResponse(code: $code, msg: $msg, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OkxBalanceResponseImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.msg, msg) || other.msg == msg) &&
            const DeepCollectionEquality().equals(other._data, _data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    code,
    msg,
    const DeepCollectionEquality().hash(_data),
  );

  /// Create a copy of OkxBalanceResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OkxBalanceResponseImplCopyWith<_$OkxBalanceResponseImpl> get copyWith =>
      __$$OkxBalanceResponseImplCopyWithImpl<_$OkxBalanceResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$OkxBalanceResponseImplToJson(this);
  }
}

abstract class _OkxBalanceResponse implements OkxBalanceResponse {
  const factory _OkxBalanceResponse({
    final String code,
    final String msg,
    final List<OkxAccountData> data,
  }) = _$OkxBalanceResponseImpl;

  factory _OkxBalanceResponse.fromJson(Map<String, dynamic> json) =
      _$OkxBalanceResponseImpl.fromJson;

  @override
  String get code;
  @override
  String get msg;
  @override
  List<OkxAccountData> get data;

  /// Create a copy of OkxBalanceResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxBalanceResponseImplCopyWith<_$OkxBalanceResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OkxAccountData _$OkxAccountDataFromJson(Map<String, dynamic> json) {
  return _OkxAccountData.fromJson(json);
}

/// @nodoc
mixin _$OkxAccountData {
  String get totalEq => throw _privateConstructorUsedError;
  String get imr =>
      throw _privateConstructorUsedError; // Ký quỹ Cross Margin tổng
  String get isoEq =>
      throw _privateConstructorUsedError; // Ký quỹ Isolated Margin tổng
  List<OkxCoinDetail> get details => throw _privateConstructorUsedError;

  /// Serializes this OkxAccountData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OkxAccountData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OkxAccountDataCopyWith<OkxAccountData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OkxAccountDataCopyWith<$Res> {
  factory $OkxAccountDataCopyWith(
    OkxAccountData value,
    $Res Function(OkxAccountData) then,
  ) = _$OkxAccountDataCopyWithImpl<$Res, OkxAccountData>;
  @useResult
  $Res call({
    String totalEq,
    String imr,
    String isoEq,
    List<OkxCoinDetail> details,
  });
}

/// @nodoc
class _$OkxAccountDataCopyWithImpl<$Res, $Val extends OkxAccountData>
    implements $OkxAccountDataCopyWith<$Res> {
  _$OkxAccountDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OkxAccountData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? totalEq = null,
    Object? imr = null,
    Object? isoEq = null,
    Object? details = null,
  }) {
    return _then(
      _value.copyWith(
            totalEq: null == totalEq
                ? _value.totalEq
                : totalEq // ignore: cast_nullable_to_non_nullable
                      as String,
            imr: null == imr
                ? _value.imr
                : imr // ignore: cast_nullable_to_non_nullable
                      as String,
            isoEq: null == isoEq
                ? _value.isoEq
                : isoEq // ignore: cast_nullable_to_non_nullable
                      as String,
            details: null == details
                ? _value.details
                : details // ignore: cast_nullable_to_non_nullable
                      as List<OkxCoinDetail>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OkxAccountDataImplCopyWith<$Res>
    implements $OkxAccountDataCopyWith<$Res> {
  factory _$$OkxAccountDataImplCopyWith(
    _$OkxAccountDataImpl value,
    $Res Function(_$OkxAccountDataImpl) then,
  ) = __$$OkxAccountDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String totalEq,
    String imr,
    String isoEq,
    List<OkxCoinDetail> details,
  });
}

/// @nodoc
class __$$OkxAccountDataImplCopyWithImpl<$Res>
    extends _$OkxAccountDataCopyWithImpl<$Res, _$OkxAccountDataImpl>
    implements _$$OkxAccountDataImplCopyWith<$Res> {
  __$$OkxAccountDataImplCopyWithImpl(
    _$OkxAccountDataImpl _value,
    $Res Function(_$OkxAccountDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OkxAccountData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? totalEq = null,
    Object? imr = null,
    Object? isoEq = null,
    Object? details = null,
  }) {
    return _then(
      _$OkxAccountDataImpl(
        totalEq: null == totalEq
            ? _value.totalEq
            : totalEq // ignore: cast_nullable_to_non_nullable
                  as String,
        imr: null == imr
            ? _value.imr
            : imr // ignore: cast_nullable_to_non_nullable
                  as String,
        isoEq: null == isoEq
            ? _value.isoEq
            : isoEq // ignore: cast_nullable_to_non_nullable
                  as String,
        details: null == details
            ? _value._details
            : details // ignore: cast_nullable_to_non_nullable
                  as List<OkxCoinDetail>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OkxAccountDataImpl implements _OkxAccountData {
  const _$OkxAccountDataImpl({
    this.totalEq = '0',
    this.imr = '0',
    this.isoEq = '0',
    final List<OkxCoinDetail> details = const [],
  }) : _details = details;

  factory _$OkxAccountDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$OkxAccountDataImplFromJson(json);

  @override
  @JsonKey()
  final String totalEq;
  @override
  @JsonKey()
  final String imr;
  // Ký quỹ Cross Margin tổng
  @override
  @JsonKey()
  final String isoEq;
  // Ký quỹ Isolated Margin tổng
  final List<OkxCoinDetail> _details;
  // Ký quỹ Isolated Margin tổng
  @override
  @JsonKey()
  List<OkxCoinDetail> get details {
    if (_details is EqualUnmodifiableListView) return _details;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_details);
  }

  @override
  String toString() {
    return 'OkxAccountData(totalEq: $totalEq, imr: $imr, isoEq: $isoEq, details: $details)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OkxAccountDataImpl &&
            (identical(other.totalEq, totalEq) || other.totalEq == totalEq) &&
            (identical(other.imr, imr) || other.imr == imr) &&
            (identical(other.isoEq, isoEq) || other.isoEq == isoEq) &&
            const DeepCollectionEquality().equals(other._details, _details));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    totalEq,
    imr,
    isoEq,
    const DeepCollectionEquality().hash(_details),
  );

  /// Create a copy of OkxAccountData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OkxAccountDataImplCopyWith<_$OkxAccountDataImpl> get copyWith =>
      __$$OkxAccountDataImplCopyWithImpl<_$OkxAccountDataImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$OkxAccountDataImplToJson(this);
  }
}

abstract class _OkxAccountData implements OkxAccountData {
  const factory _OkxAccountData({
    final String totalEq,
    final String imr,
    final String isoEq,
    final List<OkxCoinDetail> details,
  }) = _$OkxAccountDataImpl;

  factory _OkxAccountData.fromJson(Map<String, dynamic> json) =
      _$OkxAccountDataImpl.fromJson;

  @override
  String get totalEq;
  @override
  String get imr; // Ký quỹ Cross Margin tổng
  @override
  String get isoEq; // Ký quỹ Isolated Margin tổng
  @override
  List<OkxCoinDetail> get details;

  /// Create a copy of OkxAccountData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxAccountDataImplCopyWith<_$OkxAccountDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OkxCoinDetail _$OkxCoinDetailFromJson(Map<String, dynamic> json) {
  return _OkxCoinDetail.fromJson(json);
}

/// @nodoc
mixin _$OkxCoinDetail {
  String get ccy => throw _privateConstructorUsedError;
  String get cashBal => throw _privateConstructorUsedError;
  String get availBal =>
      throw _privateConstructorUsedError; // Tiền dư/khả dụng vật lý (THÊM MỚI)
  String get availEq =>
      throw _privateConstructorUsedError; // Tiền dư/khả dụng margin (THÊM MỚI)
  String get eq => throw _privateConstructorUsedError;
  String get eqUsd => throw _privateConstructorUsedError;
  String get upl => throw _privateConstructorUsedError;
  String get frozenBal => throw _privateConstructorUsedError;
  String get ordFrozen => throw _privateConstructorUsedError;
  String get imr => throw _privateConstructorUsedError;
  String get isoEq => throw _privateConstructorUsedError;
  String get isoUpl => throw _privateConstructorUsedError;

  /// Serializes this OkxCoinDetail to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OkxCoinDetail
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OkxCoinDetailCopyWith<OkxCoinDetail> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OkxCoinDetailCopyWith<$Res> {
  factory $OkxCoinDetailCopyWith(
    OkxCoinDetail value,
    $Res Function(OkxCoinDetail) then,
  ) = _$OkxCoinDetailCopyWithImpl<$Res, OkxCoinDetail>;
  @useResult
  $Res call({
    String ccy,
    String cashBal,
    String availBal,
    String availEq,
    String eq,
    String eqUsd,
    String upl,
    String frozenBal,
    String ordFrozen,
    String imr,
    String isoEq,
    String isoUpl,
  });
}

/// @nodoc
class _$OkxCoinDetailCopyWithImpl<$Res, $Val extends OkxCoinDetail>
    implements $OkxCoinDetailCopyWith<$Res> {
  _$OkxCoinDetailCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OkxCoinDetail
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ccy = null,
    Object? cashBal = null,
    Object? availBal = null,
    Object? availEq = null,
    Object? eq = null,
    Object? eqUsd = null,
    Object? upl = null,
    Object? frozenBal = null,
    Object? ordFrozen = null,
    Object? imr = null,
    Object? isoEq = null,
    Object? isoUpl = null,
  }) {
    return _then(
      _value.copyWith(
            ccy: null == ccy
                ? _value.ccy
                : ccy // ignore: cast_nullable_to_non_nullable
                      as String,
            cashBal: null == cashBal
                ? _value.cashBal
                : cashBal // ignore: cast_nullable_to_non_nullable
                      as String,
            availBal: null == availBal
                ? _value.availBal
                : availBal // ignore: cast_nullable_to_non_nullable
                      as String,
            availEq: null == availEq
                ? _value.availEq
                : availEq // ignore: cast_nullable_to_non_nullable
                      as String,
            eq: null == eq
                ? _value.eq
                : eq // ignore: cast_nullable_to_non_nullable
                      as String,
            eqUsd: null == eqUsd
                ? _value.eqUsd
                : eqUsd // ignore: cast_nullable_to_non_nullable
                      as String,
            upl: null == upl
                ? _value.upl
                : upl // ignore: cast_nullable_to_non_nullable
                      as String,
            frozenBal: null == frozenBal
                ? _value.frozenBal
                : frozenBal // ignore: cast_nullable_to_non_nullable
                      as String,
            ordFrozen: null == ordFrozen
                ? _value.ordFrozen
                : ordFrozen // ignore: cast_nullable_to_non_nullable
                      as String,
            imr: null == imr
                ? _value.imr
                : imr // ignore: cast_nullable_to_non_nullable
                      as String,
            isoEq: null == isoEq
                ? _value.isoEq
                : isoEq // ignore: cast_nullable_to_non_nullable
                      as String,
            isoUpl: null == isoUpl
                ? _value.isoUpl
                : isoUpl // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OkxCoinDetailImplCopyWith<$Res>
    implements $OkxCoinDetailCopyWith<$Res> {
  factory _$$OkxCoinDetailImplCopyWith(
    _$OkxCoinDetailImpl value,
    $Res Function(_$OkxCoinDetailImpl) then,
  ) = __$$OkxCoinDetailImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String ccy,
    String cashBal,
    String availBal,
    String availEq,
    String eq,
    String eqUsd,
    String upl,
    String frozenBal,
    String ordFrozen,
    String imr,
    String isoEq,
    String isoUpl,
  });
}

/// @nodoc
class __$$OkxCoinDetailImplCopyWithImpl<$Res>
    extends _$OkxCoinDetailCopyWithImpl<$Res, _$OkxCoinDetailImpl>
    implements _$$OkxCoinDetailImplCopyWith<$Res> {
  __$$OkxCoinDetailImplCopyWithImpl(
    _$OkxCoinDetailImpl _value,
    $Res Function(_$OkxCoinDetailImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OkxCoinDetail
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ccy = null,
    Object? cashBal = null,
    Object? availBal = null,
    Object? availEq = null,
    Object? eq = null,
    Object? eqUsd = null,
    Object? upl = null,
    Object? frozenBal = null,
    Object? ordFrozen = null,
    Object? imr = null,
    Object? isoEq = null,
    Object? isoUpl = null,
  }) {
    return _then(
      _$OkxCoinDetailImpl(
        ccy: null == ccy
            ? _value.ccy
            : ccy // ignore: cast_nullable_to_non_nullable
                  as String,
        cashBal: null == cashBal
            ? _value.cashBal
            : cashBal // ignore: cast_nullable_to_non_nullable
                  as String,
        availBal: null == availBal
            ? _value.availBal
            : availBal // ignore: cast_nullable_to_non_nullable
                  as String,
        availEq: null == availEq
            ? _value.availEq
            : availEq // ignore: cast_nullable_to_non_nullable
                  as String,
        eq: null == eq
            ? _value.eq
            : eq // ignore: cast_nullable_to_non_nullable
                  as String,
        eqUsd: null == eqUsd
            ? _value.eqUsd
            : eqUsd // ignore: cast_nullable_to_non_nullable
                  as String,
        upl: null == upl
            ? _value.upl
            : upl // ignore: cast_nullable_to_non_nullable
                  as String,
        frozenBal: null == frozenBal
            ? _value.frozenBal
            : frozenBal // ignore: cast_nullable_to_non_nullable
                  as String,
        ordFrozen: null == ordFrozen
            ? _value.ordFrozen
            : ordFrozen // ignore: cast_nullable_to_non_nullable
                  as String,
        imr: null == imr
            ? _value.imr
            : imr // ignore: cast_nullable_to_non_nullable
                  as String,
        isoEq: null == isoEq
            ? _value.isoEq
            : isoEq // ignore: cast_nullable_to_non_nullable
                  as String,
        isoUpl: null == isoUpl
            ? _value.isoUpl
            : isoUpl // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OkxCoinDetailImpl implements _OkxCoinDetail {
  const _$OkxCoinDetailImpl({
    this.ccy = '',
    this.cashBal = '0',
    this.availBal = '0',
    this.availEq = '0',
    this.eq = '0',
    this.eqUsd = '0',
    this.upl = '0',
    this.frozenBal = '0',
    this.ordFrozen = '0',
    this.imr = '0',
    this.isoEq = '0',
    this.isoUpl = '0',
  });

  factory _$OkxCoinDetailImpl.fromJson(Map<String, dynamic> json) =>
      _$$OkxCoinDetailImplFromJson(json);

  @override
  @JsonKey()
  final String ccy;
  @override
  @JsonKey()
  final String cashBal;
  @override
  @JsonKey()
  final String availBal;
  // Tiền dư/khả dụng vật lý (THÊM MỚI)
  @override
  @JsonKey()
  final String availEq;
  // Tiền dư/khả dụng margin (THÊM MỚI)
  @override
  @JsonKey()
  final String eq;
  @override
  @JsonKey()
  final String eqUsd;
  @override
  @JsonKey()
  final String upl;
  @override
  @JsonKey()
  final String frozenBal;
  @override
  @JsonKey()
  final String ordFrozen;
  @override
  @JsonKey()
  final String imr;
  @override
  @JsonKey()
  final String isoEq;
  @override
  @JsonKey()
  final String isoUpl;

  @override
  String toString() {
    return 'OkxCoinDetail(ccy: $ccy, cashBal: $cashBal, availBal: $availBal, availEq: $availEq, eq: $eq, eqUsd: $eqUsd, upl: $upl, frozenBal: $frozenBal, ordFrozen: $ordFrozen, imr: $imr, isoEq: $isoEq, isoUpl: $isoUpl)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OkxCoinDetailImpl &&
            (identical(other.ccy, ccy) || other.ccy == ccy) &&
            (identical(other.cashBal, cashBal) || other.cashBal == cashBal) &&
            (identical(other.availBal, availBal) ||
                other.availBal == availBal) &&
            (identical(other.availEq, availEq) || other.availEq == availEq) &&
            (identical(other.eq, eq) || other.eq == eq) &&
            (identical(other.eqUsd, eqUsd) || other.eqUsd == eqUsd) &&
            (identical(other.upl, upl) || other.upl == upl) &&
            (identical(other.frozenBal, frozenBal) ||
                other.frozenBal == frozenBal) &&
            (identical(other.ordFrozen, ordFrozen) ||
                other.ordFrozen == ordFrozen) &&
            (identical(other.imr, imr) || other.imr == imr) &&
            (identical(other.isoEq, isoEq) || other.isoEq == isoEq) &&
            (identical(other.isoUpl, isoUpl) || other.isoUpl == isoUpl));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    ccy,
    cashBal,
    availBal,
    availEq,
    eq,
    eqUsd,
    upl,
    frozenBal,
    ordFrozen,
    imr,
    isoEq,
    isoUpl,
  );

  /// Create a copy of OkxCoinDetail
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OkxCoinDetailImplCopyWith<_$OkxCoinDetailImpl> get copyWith =>
      __$$OkxCoinDetailImplCopyWithImpl<_$OkxCoinDetailImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OkxCoinDetailImplToJson(this);
  }
}

abstract class _OkxCoinDetail implements OkxCoinDetail {
  const factory _OkxCoinDetail({
    final String ccy,
    final String cashBal,
    final String availBal,
    final String availEq,
    final String eq,
    final String eqUsd,
    final String upl,
    final String frozenBal,
    final String ordFrozen,
    final String imr,
    final String isoEq,
    final String isoUpl,
  }) = _$OkxCoinDetailImpl;

  factory _OkxCoinDetail.fromJson(Map<String, dynamic> json) =
      _$OkxCoinDetailImpl.fromJson;

  @override
  String get ccy;
  @override
  String get cashBal;
  @override
  String get availBal; // Tiền dư/khả dụng vật lý (THÊM MỚI)
  @override
  String get availEq; // Tiền dư/khả dụng margin (THÊM MỚI)
  @override
  String get eq;
  @override
  String get eqUsd;
  @override
  String get upl;
  @override
  String get frozenBal;
  @override
  String get ordFrozen;
  @override
  String get imr;
  @override
  String get isoEq;
  @override
  String get isoUpl;

  /// Create a copy of OkxCoinDetail
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxCoinDetailImplCopyWith<_$OkxCoinDetailImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
