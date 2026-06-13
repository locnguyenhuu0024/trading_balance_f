// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'okx_order_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

OkxOrderResponse _$OkxOrderResponseFromJson(Map<String, dynamic> json) {
  return _OkxOrderResponse.fromJson(json);
}

/// @nodoc
mixin _$OkxOrderResponse {
  String get code => throw _privateConstructorUsedError;
  String get msg => throw _privateConstructorUsedError;
  List<OkxOrder> get data => throw _privateConstructorUsedError;

  /// Serializes this OkxOrderResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OkxOrderResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OkxOrderResponseCopyWith<OkxOrderResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OkxOrderResponseCopyWith<$Res> {
  factory $OkxOrderResponseCopyWith(
    OkxOrderResponse value,
    $Res Function(OkxOrderResponse) then,
  ) = _$OkxOrderResponseCopyWithImpl<$Res, OkxOrderResponse>;
  @useResult
  $Res call({String code, String msg, List<OkxOrder> data});
}

/// @nodoc
class _$OkxOrderResponseCopyWithImpl<$Res, $Val extends OkxOrderResponse>
    implements $OkxOrderResponseCopyWith<$Res> {
  _$OkxOrderResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OkxOrderResponse
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
                      as List<OkxOrder>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OkxOrderResponseImplCopyWith<$Res>
    implements $OkxOrderResponseCopyWith<$Res> {
  factory _$$OkxOrderResponseImplCopyWith(
    _$OkxOrderResponseImpl value,
    $Res Function(_$OkxOrderResponseImpl) then,
  ) = __$$OkxOrderResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String msg, List<OkxOrder> data});
}

/// @nodoc
class __$$OkxOrderResponseImplCopyWithImpl<$Res>
    extends _$OkxOrderResponseCopyWithImpl<$Res, _$OkxOrderResponseImpl>
    implements _$$OkxOrderResponseImplCopyWith<$Res> {
  __$$OkxOrderResponseImplCopyWithImpl(
    _$OkxOrderResponseImpl _value,
    $Res Function(_$OkxOrderResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OkxOrderResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? code = null, Object? msg = null, Object? data = null}) {
    return _then(
      _$OkxOrderResponseImpl(
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
                  as List<OkxOrder>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OkxOrderResponseImpl implements _OkxOrderResponse {
  const _$OkxOrderResponseImpl({
    this.code = '0',
    this.msg = '',
    final List<OkxOrder> data = const [],
  }) : _data = data;

  factory _$OkxOrderResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$OkxOrderResponseImplFromJson(json);

  @override
  @JsonKey()
  final String code;
  @override
  @JsonKey()
  final String msg;
  final List<OkxOrder> _data;
  @override
  @JsonKey()
  List<OkxOrder> get data {
    if (_data is EqualUnmodifiableListView) return _data;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_data);
  }

  @override
  String toString() {
    return 'OkxOrderResponse(code: $code, msg: $msg, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OkxOrderResponseImpl &&
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

  /// Create a copy of OkxOrderResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OkxOrderResponseImplCopyWith<_$OkxOrderResponseImpl> get copyWith =>
      __$$OkxOrderResponseImplCopyWithImpl<_$OkxOrderResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$OkxOrderResponseImplToJson(this);
  }
}

abstract class _OkxOrderResponse implements OkxOrderResponse {
  const factory _OkxOrderResponse({
    final String code,
    final String msg,
    final List<OkxOrder> data,
  }) = _$OkxOrderResponseImpl;

  factory _OkxOrderResponse.fromJson(Map<String, dynamic> json) =
      _$OkxOrderResponseImpl.fromJson;

  @override
  String get code;
  @override
  String get msg;
  @override
  List<OkxOrder> get data;

  /// Create a copy of OkxOrderResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxOrderResponseImplCopyWith<_$OkxOrderResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OkxOrder _$OkxOrderFromJson(Map<String, dynamic> json) {
  return _OkxOrder.fromJson(json);
}

/// @nodoc
mixin _$OkxOrder {
  String get instId =>
      throw _privateConstructorUsedError; // Cặp giao dịch (VD: BTC-USDT)
  String get instType =>
      throw _privateConstructorUsedError; // Loại (SPOT, MARGIN, SWAP, FUTURES)
  String get side =>
      throw _privateConstructorUsedError; // Chiều giao dịch (buy, sell)
  String get px => throw _privateConstructorUsedError; // Giá đặt lệnh
  String get sz =>
      throw _privateConstructorUsedError; // Kích thước/Số lượng lệnh
  String get state =>
      throw _privateConstructorUsedError; // Trạng thái (live, filled, canceled)
  String get lever =>
      throw _privateConstructorUsedError; // Đòn bẩy (Dành cho margin/futures)
  String get cTime =>
      throw _privateConstructorUsedError; // Thời gian tạo lệnh (Unix Timestamp ms)
  String get pnl => throw _privateConstructorUsedError;

  /// Serializes this OkxOrder to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OkxOrder
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OkxOrderCopyWith<OkxOrder> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OkxOrderCopyWith<$Res> {
  factory $OkxOrderCopyWith(OkxOrder value, $Res Function(OkxOrder) then) =
      _$OkxOrderCopyWithImpl<$Res, OkxOrder>;
  @useResult
  $Res call({
    String instId,
    String instType,
    String side,
    String px,
    String sz,
    String state,
    String lever,
    String cTime,
    String pnl,
  });
}

/// @nodoc
class _$OkxOrderCopyWithImpl<$Res, $Val extends OkxOrder>
    implements $OkxOrderCopyWith<$Res> {
  _$OkxOrderCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OkxOrder
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? instId = null,
    Object? instType = null,
    Object? side = null,
    Object? px = null,
    Object? sz = null,
    Object? state = null,
    Object? lever = null,
    Object? cTime = null,
    Object? pnl = null,
  }) {
    return _then(
      _value.copyWith(
            instId: null == instId
                ? _value.instId
                : instId // ignore: cast_nullable_to_non_nullable
                      as String,
            instType: null == instType
                ? _value.instType
                : instType // ignore: cast_nullable_to_non_nullable
                      as String,
            side: null == side
                ? _value.side
                : side // ignore: cast_nullable_to_non_nullable
                      as String,
            px: null == px
                ? _value.px
                : px // ignore: cast_nullable_to_non_nullable
                      as String,
            sz: null == sz
                ? _value.sz
                : sz // ignore: cast_nullable_to_non_nullable
                      as String,
            state: null == state
                ? _value.state
                : state // ignore: cast_nullable_to_non_nullable
                      as String,
            lever: null == lever
                ? _value.lever
                : lever // ignore: cast_nullable_to_non_nullable
                      as String,
            cTime: null == cTime
                ? _value.cTime
                : cTime // ignore: cast_nullable_to_non_nullable
                      as String,
            pnl: null == pnl
                ? _value.pnl
                : pnl // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OkxOrderImplCopyWith<$Res>
    implements $OkxOrderCopyWith<$Res> {
  factory _$$OkxOrderImplCopyWith(
    _$OkxOrderImpl value,
    $Res Function(_$OkxOrderImpl) then,
  ) = __$$OkxOrderImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String instId,
    String instType,
    String side,
    String px,
    String sz,
    String state,
    String lever,
    String cTime,
    String pnl,
  });
}

/// @nodoc
class __$$OkxOrderImplCopyWithImpl<$Res>
    extends _$OkxOrderCopyWithImpl<$Res, _$OkxOrderImpl>
    implements _$$OkxOrderImplCopyWith<$Res> {
  __$$OkxOrderImplCopyWithImpl(
    _$OkxOrderImpl _value,
    $Res Function(_$OkxOrderImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OkxOrder
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? instId = null,
    Object? instType = null,
    Object? side = null,
    Object? px = null,
    Object? sz = null,
    Object? state = null,
    Object? lever = null,
    Object? cTime = null,
    Object? pnl = null,
  }) {
    return _then(
      _$OkxOrderImpl(
        instId: null == instId
            ? _value.instId
            : instId // ignore: cast_nullable_to_non_nullable
                  as String,
        instType: null == instType
            ? _value.instType
            : instType // ignore: cast_nullable_to_non_nullable
                  as String,
        side: null == side
            ? _value.side
            : side // ignore: cast_nullable_to_non_nullable
                  as String,
        px: null == px
            ? _value.px
            : px // ignore: cast_nullable_to_non_nullable
                  as String,
        sz: null == sz
            ? _value.sz
            : sz // ignore: cast_nullable_to_non_nullable
                  as String,
        state: null == state
            ? _value.state
            : state // ignore: cast_nullable_to_non_nullable
                  as String,
        lever: null == lever
            ? _value.lever
            : lever // ignore: cast_nullable_to_non_nullable
                  as String,
        cTime: null == cTime
            ? _value.cTime
            : cTime // ignore: cast_nullable_to_non_nullable
                  as String,
        pnl: null == pnl
            ? _value.pnl
            : pnl // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OkxOrderImpl implements _OkxOrder {
  const _$OkxOrderImpl({
    this.instId = '',
    this.instType = '',
    this.side = '',
    this.px = '',
    this.sz = '',
    this.state = '',
    this.lever = '',
    this.cTime = '',
    this.pnl = '',
  });

  factory _$OkxOrderImpl.fromJson(Map<String, dynamic> json) =>
      _$$OkxOrderImplFromJson(json);

  @override
  @JsonKey()
  final String instId;
  // Cặp giao dịch (VD: BTC-USDT)
  @override
  @JsonKey()
  final String instType;
  // Loại (SPOT, MARGIN, SWAP, FUTURES)
  @override
  @JsonKey()
  final String side;
  // Chiều giao dịch (buy, sell)
  @override
  @JsonKey()
  final String px;
  // Giá đặt lệnh
  @override
  @JsonKey()
  final String sz;
  // Kích thước/Số lượng lệnh
  @override
  @JsonKey()
  final String state;
  // Trạng thái (live, filled, canceled)
  @override
  @JsonKey()
  final String lever;
  // Đòn bẩy (Dành cho margin/futures)
  @override
  @JsonKey()
  final String cTime;
  // Thời gian tạo lệnh (Unix Timestamp ms)
  @override
  @JsonKey()
  final String pnl;

  @override
  String toString() {
    return 'OkxOrder(instId: $instId, instType: $instType, side: $side, px: $px, sz: $sz, state: $state, lever: $lever, cTime: $cTime, pnl: $pnl)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OkxOrderImpl &&
            (identical(other.instId, instId) || other.instId == instId) &&
            (identical(other.instType, instType) ||
                other.instType == instType) &&
            (identical(other.side, side) || other.side == side) &&
            (identical(other.px, px) || other.px == px) &&
            (identical(other.sz, sz) || other.sz == sz) &&
            (identical(other.state, state) || other.state == state) &&
            (identical(other.lever, lever) || other.lever == lever) &&
            (identical(other.cTime, cTime) || other.cTime == cTime) &&
            (identical(other.pnl, pnl) || other.pnl == pnl));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    instId,
    instType,
    side,
    px,
    sz,
    state,
    lever,
    cTime,
    pnl,
  );

  /// Create a copy of OkxOrder
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OkxOrderImplCopyWith<_$OkxOrderImpl> get copyWith =>
      __$$OkxOrderImplCopyWithImpl<_$OkxOrderImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OkxOrderImplToJson(this);
  }
}

abstract class _OkxOrder implements OkxOrder {
  const factory _OkxOrder({
    final String instId,
    final String instType,
    final String side,
    final String px,
    final String sz,
    final String state,
    final String lever,
    final String cTime,
    final String pnl,
  }) = _$OkxOrderImpl;

  factory _OkxOrder.fromJson(Map<String, dynamic> json) =
      _$OkxOrderImpl.fromJson;

  @override
  String get instId; // Cặp giao dịch (VD: BTC-USDT)
  @override
  String get instType; // Loại (SPOT, MARGIN, SWAP, FUTURES)
  @override
  String get side; // Chiều giao dịch (buy, sell)
  @override
  String get px; // Giá đặt lệnh
  @override
  String get sz; // Kích thước/Số lượng lệnh
  @override
  String get state; // Trạng thái (live, filled, canceled)
  @override
  String get lever; // Đòn bẩy (Dành cho margin/futures)
  @override
  String get cTime; // Thời gian tạo lệnh (Unix Timestamp ms)
  @override
  String get pnl;

  /// Create a copy of OkxOrder
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxOrderImplCopyWith<_$OkxOrderImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
