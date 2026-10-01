// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'okx_position_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

OkxPosition _$OkxPositionFromJson(Map<String, dynamic> json) {
  return _OkxPosition.fromJson(json);
}

/// @nodoc
mixin _$OkxPosition {
  String get instId =>
      throw _privateConstructorUsedError; // Cặp giao dịch (VD: BTC-USDT-SWAP)
  String get posSide =>
      throw _privateConstructorUsedError; // Chiều vị thế (long, short, net)
  String get pos =>
      throw _privateConstructorUsedError; // Kích thước vị thế (Số lượng)
  String get avgPx =>
      throw _privateConstructorUsedError; // Giá vào lệnh trung bình (Entry Price)
  String get markPx =>
      throw _privateConstructorUsedError; // Giá đánh dấu hiện hành (Mark Price)
  String get lever => throw _privateConstructorUsedError; // Đòn bẩy hiện tại
  String get liqPx =>
      throw _privateConstructorUsedError; // Giá thanh lý ước tính
  String get upl =>
      throw _privateConstructorUsedError; // Lãi/lỗ chưa thực hiện (Unrealized PnL - USD)
  String get uplRatio => throw _privateConstructorUsedError; // Tỷ lệ Lãi/lỗ
  String get mgnMode =>
      throw _privateConstructorUsedError; // Chế độ Margin (cross hoặc isolated)
  String get notionalUsd =>
      throw _privateConstructorUsedError; // Giá trị danh nghĩa vị thế theo USD
  String get instType => throw _privateConstructorUsedError;
  String get positionId => throw _privateConstructorUsedError;
  String get signedSize => throw _privateConstructorUsedError;
  String get size => throw _privateConstructorUsedError;
  String get direction => throw _privateConstructorUsedError;
  String get marginCurrency => throw _privateConstructorUsedError;
  String get positionCurrency => throw _privateConstructorUsedError;
  Map<String, dynamic> get identity => throw _privateConstructorUsedError;
  Map<String, dynamic> get eligibleActions =>
      throw _privateConstructorUsedError;

  /// Serializes this OkxPosition to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OkxPosition
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OkxPositionCopyWith<OkxPosition> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OkxPositionCopyWith<$Res> {
  factory $OkxPositionCopyWith(
    OkxPosition value,
    $Res Function(OkxPosition) then,
  ) = _$OkxPositionCopyWithImpl<$Res, OkxPosition>;
  @useResult
  $Res call({
    String instId,
    String posSide,
    String pos,
    String avgPx,
    String markPx,
    String lever,
    String liqPx,
    String upl,
    String uplRatio,
    String mgnMode,
    String notionalUsd,
    String instType,
    String positionId,
    String signedSize,
    String size,
    String direction,
    String marginCurrency,
    String positionCurrency,
    Map<String, dynamic> identity,
    Map<String, dynamic> eligibleActions,
  });
}

/// @nodoc
class _$OkxPositionCopyWithImpl<$Res, $Val extends OkxPosition>
    implements $OkxPositionCopyWith<$Res> {
  _$OkxPositionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OkxPosition
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? instId = null,
    Object? posSide = null,
    Object? pos = null,
    Object? avgPx = null,
    Object? markPx = null,
    Object? lever = null,
    Object? liqPx = null,
    Object? upl = null,
    Object? uplRatio = null,
    Object? mgnMode = null,
    Object? notionalUsd = null,
    Object? instType = null,
    Object? positionId = null,
    Object? signedSize = null,
    Object? size = null,
    Object? direction = null,
    Object? marginCurrency = null,
    Object? positionCurrency = null,
    Object? identity = null,
    Object? eligibleActions = null,
  }) {
    return _then(
      _value.copyWith(
            instId: null == instId
                ? _value.instId
                : instId // ignore: cast_nullable_to_non_nullable
                      as String,
            posSide: null == posSide
                ? _value.posSide
                : posSide // ignore: cast_nullable_to_non_nullable
                      as String,
            pos: null == pos
                ? _value.pos
                : pos // ignore: cast_nullable_to_non_nullable
                      as String,
            avgPx: null == avgPx
                ? _value.avgPx
                : avgPx // ignore: cast_nullable_to_non_nullable
                      as String,
            markPx: null == markPx
                ? _value.markPx
                : markPx // ignore: cast_nullable_to_non_nullable
                      as String,
            lever: null == lever
                ? _value.lever
                : lever // ignore: cast_nullable_to_non_nullable
                      as String,
            liqPx: null == liqPx
                ? _value.liqPx
                : liqPx // ignore: cast_nullable_to_non_nullable
                      as String,
            upl: null == upl
                ? _value.upl
                : upl // ignore: cast_nullable_to_non_nullable
                      as String,
            uplRatio: null == uplRatio
                ? _value.uplRatio
                : uplRatio // ignore: cast_nullable_to_non_nullable
                      as String,
            mgnMode: null == mgnMode
                ? _value.mgnMode
                : mgnMode // ignore: cast_nullable_to_non_nullable
                      as String,
            notionalUsd: null == notionalUsd
                ? _value.notionalUsd
                : notionalUsd // ignore: cast_nullable_to_non_nullable
                      as String,
            instType: null == instType
                ? _value.instType
                : instType // ignore: cast_nullable_to_non_nullable
                      as String,
            positionId: null == positionId
                ? _value.positionId
                : positionId // ignore: cast_nullable_to_non_nullable
                      as String,
            signedSize: null == signedSize
                ? _value.signedSize
                : signedSize // ignore: cast_nullable_to_non_nullable
                      as String,
            size: null == size
                ? _value.size
                : size // ignore: cast_nullable_to_non_nullable
                      as String,
            direction: null == direction
                ? _value.direction
                : direction // ignore: cast_nullable_to_non_nullable
                      as String,
            marginCurrency: null == marginCurrency
                ? _value.marginCurrency
                : marginCurrency // ignore: cast_nullable_to_non_nullable
                      as String,
            positionCurrency: null == positionCurrency
                ? _value.positionCurrency
                : positionCurrency // ignore: cast_nullable_to_non_nullable
                      as String,
            identity: null == identity
                ? _value.identity
                : identity // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>,
            eligibleActions: null == eligibleActions
                ? _value.eligibleActions
                : eligibleActions // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OkxPositionImplCopyWith<$Res>
    implements $OkxPositionCopyWith<$Res> {
  factory _$$OkxPositionImplCopyWith(
    _$OkxPositionImpl value,
    $Res Function(_$OkxPositionImpl) then,
  ) = __$$OkxPositionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String instId,
    String posSide,
    String pos,
    String avgPx,
    String markPx,
    String lever,
    String liqPx,
    String upl,
    String uplRatio,
    String mgnMode,
    String notionalUsd,
    String instType,
    String positionId,
    String signedSize,
    String size,
    String direction,
    String marginCurrency,
    String positionCurrency,
    Map<String, dynamic> identity,
    Map<String, dynamic> eligibleActions,
  });
}

/// @nodoc
class __$$OkxPositionImplCopyWithImpl<$Res>
    extends _$OkxPositionCopyWithImpl<$Res, _$OkxPositionImpl>
    implements _$$OkxPositionImplCopyWith<$Res> {
  __$$OkxPositionImplCopyWithImpl(
    _$OkxPositionImpl _value,
    $Res Function(_$OkxPositionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OkxPosition
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? instId = null,
    Object? posSide = null,
    Object? pos = null,
    Object? avgPx = null,
    Object? markPx = null,
    Object? lever = null,
    Object? liqPx = null,
    Object? upl = null,
    Object? uplRatio = null,
    Object? mgnMode = null,
    Object? notionalUsd = null,
    Object? instType = null,
    Object? positionId = null,
    Object? signedSize = null,
    Object? size = null,
    Object? direction = null,
    Object? marginCurrency = null,
    Object? positionCurrency = null,
    Object? identity = null,
    Object? eligibleActions = null,
  }) {
    return _then(
      _$OkxPositionImpl(
        instId: null == instId
            ? _value.instId
            : instId // ignore: cast_nullable_to_non_nullable
                  as String,
        posSide: null == posSide
            ? _value.posSide
            : posSide // ignore: cast_nullable_to_non_nullable
                  as String,
        pos: null == pos
            ? _value.pos
            : pos // ignore: cast_nullable_to_non_nullable
                  as String,
        avgPx: null == avgPx
            ? _value.avgPx
            : avgPx // ignore: cast_nullable_to_non_nullable
                  as String,
        markPx: null == markPx
            ? _value.markPx
            : markPx // ignore: cast_nullable_to_non_nullable
                  as String,
        lever: null == lever
            ? _value.lever
            : lever // ignore: cast_nullable_to_non_nullable
                  as String,
        liqPx: null == liqPx
            ? _value.liqPx
            : liqPx // ignore: cast_nullable_to_non_nullable
                  as String,
        upl: null == upl
            ? _value.upl
            : upl // ignore: cast_nullable_to_non_nullable
                  as String,
        uplRatio: null == uplRatio
            ? _value.uplRatio
            : uplRatio // ignore: cast_nullable_to_non_nullable
                  as String,
        mgnMode: null == mgnMode
            ? _value.mgnMode
            : mgnMode // ignore: cast_nullable_to_non_nullable
                  as String,
        notionalUsd: null == notionalUsd
            ? _value.notionalUsd
            : notionalUsd // ignore: cast_nullable_to_non_nullable
                  as String,
        instType: null == instType
            ? _value.instType
            : instType // ignore: cast_nullable_to_non_nullable
                  as String,
        positionId: null == positionId
            ? _value.positionId
            : positionId // ignore: cast_nullable_to_non_nullable
                  as String,
        signedSize: null == signedSize
            ? _value.signedSize
            : signedSize // ignore: cast_nullable_to_non_nullable
                  as String,
        size: null == size
            ? _value.size
            : size // ignore: cast_nullable_to_non_nullable
                  as String,
        direction: null == direction
            ? _value.direction
            : direction // ignore: cast_nullable_to_non_nullable
                  as String,
        marginCurrency: null == marginCurrency
            ? _value.marginCurrency
            : marginCurrency // ignore: cast_nullable_to_non_nullable
                  as String,
        positionCurrency: null == positionCurrency
            ? _value.positionCurrency
            : positionCurrency // ignore: cast_nullable_to_non_nullable
                  as String,
        identity: null == identity
            ? _value._identity
            : identity // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>,
        eligibleActions: null == eligibleActions
            ? _value._eligibleActions
            : eligibleActions // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OkxPositionImpl implements _OkxPosition {
  const _$OkxPositionImpl({
    this.instId = '',
    this.posSide = '',
    this.pos = '',
    this.avgPx = '',
    this.markPx = '',
    this.lever = '',
    this.liqPx = '',
    this.upl = '',
    this.uplRatio = '',
    this.mgnMode = '',
    this.notionalUsd = '',
    this.instType = '',
    this.positionId = '',
    this.signedSize = '',
    this.size = '',
    this.direction = '',
    this.marginCurrency = '',
    this.positionCurrency = '',
    final Map<String, dynamic> identity = const <String, dynamic>{},
    final Map<String, dynamic> eligibleActions = const <String, dynamic>{},
  }) : _identity = identity,
       _eligibleActions = eligibleActions;

  factory _$OkxPositionImpl.fromJson(Map<String, dynamic> json) =>
      _$$OkxPositionImplFromJson(json);

  @override
  @JsonKey()
  final String instId;
  // Cặp giao dịch (VD: BTC-USDT-SWAP)
  @override
  @JsonKey()
  final String posSide;
  // Chiều vị thế (long, short, net)
  @override
  @JsonKey()
  final String pos;
  // Kích thước vị thế (Số lượng)
  @override
  @JsonKey()
  final String avgPx;
  // Giá vào lệnh trung bình (Entry Price)
  @override
  @JsonKey()
  final String markPx;
  // Giá đánh dấu hiện hành (Mark Price)
  @override
  @JsonKey()
  final String lever;
  // Đòn bẩy hiện tại
  @override
  @JsonKey()
  final String liqPx;
  // Giá thanh lý ước tính
  @override
  @JsonKey()
  final String upl;
  // Lãi/lỗ chưa thực hiện (Unrealized PnL - USD)
  @override
  @JsonKey()
  final String uplRatio;
  // Tỷ lệ Lãi/lỗ
  @override
  @JsonKey()
  final String mgnMode;
  // Chế độ Margin (cross hoặc isolated)
  @override
  @JsonKey()
  final String notionalUsd;
  // Giá trị danh nghĩa vị thế theo USD
  @override
  @JsonKey()
  final String instType;
  @override
  @JsonKey()
  final String positionId;
  @override
  @JsonKey()
  final String signedSize;
  @override
  @JsonKey()
  final String size;
  @override
  @JsonKey()
  final String direction;
  @override
  @JsonKey()
  final String marginCurrency;
  @override
  @JsonKey()
  final String positionCurrency;
  final Map<String, dynamic> _identity;
  @override
  @JsonKey()
  Map<String, dynamic> get identity {
    if (_identity is EqualUnmodifiableMapView) return _identity;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_identity);
  }

  final Map<String, dynamic> _eligibleActions;
  @override
  @JsonKey()
  Map<String, dynamic> get eligibleActions {
    if (_eligibleActions is EqualUnmodifiableMapView) return _eligibleActions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_eligibleActions);
  }

  @override
  String toString() {
    return 'OkxPosition(instId: $instId, posSide: $posSide, pos: $pos, avgPx: $avgPx, markPx: $markPx, lever: $lever, liqPx: $liqPx, upl: $upl, uplRatio: $uplRatio, mgnMode: $mgnMode, notionalUsd: $notionalUsd, instType: $instType, positionId: $positionId, signedSize: $signedSize, size: $size, direction: $direction, marginCurrency: $marginCurrency, positionCurrency: $positionCurrency, identity: $identity, eligibleActions: $eligibleActions)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OkxPositionImpl &&
            (identical(other.instId, instId) || other.instId == instId) &&
            (identical(other.posSide, posSide) || other.posSide == posSide) &&
            (identical(other.pos, pos) || other.pos == pos) &&
            (identical(other.avgPx, avgPx) || other.avgPx == avgPx) &&
            (identical(other.markPx, markPx) || other.markPx == markPx) &&
            (identical(other.lever, lever) || other.lever == lever) &&
            (identical(other.liqPx, liqPx) || other.liqPx == liqPx) &&
            (identical(other.upl, upl) || other.upl == upl) &&
            (identical(other.uplRatio, uplRatio) ||
                other.uplRatio == uplRatio) &&
            (identical(other.mgnMode, mgnMode) || other.mgnMode == mgnMode) &&
            (identical(other.notionalUsd, notionalUsd) ||
                other.notionalUsd == notionalUsd) &&
            (identical(other.instType, instType) ||
                other.instType == instType) &&
            (identical(other.positionId, positionId) ||
                other.positionId == positionId) &&
            (identical(other.signedSize, signedSize) ||
                other.signedSize == signedSize) &&
            (identical(other.size, size) || other.size == size) &&
            (identical(other.direction, direction) ||
                other.direction == direction) &&
            (identical(other.marginCurrency, marginCurrency) ||
                other.marginCurrency == marginCurrency) &&
            (identical(other.positionCurrency, positionCurrency) ||
                other.positionCurrency == positionCurrency) &&
            const DeepCollectionEquality().equals(other._identity, _identity) &&
            const DeepCollectionEquality().equals(
              other._eligibleActions,
              _eligibleActions,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    instId,
    posSide,
    pos,
    avgPx,
    markPx,
    lever,
    liqPx,
    upl,
    uplRatio,
    mgnMode,
    notionalUsd,
    instType,
    positionId,
    signedSize,
    size,
    direction,
    marginCurrency,
    positionCurrency,
    const DeepCollectionEquality().hash(_identity),
    const DeepCollectionEquality().hash(_eligibleActions),
  ]);

  /// Create a copy of OkxPosition
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OkxPositionImplCopyWith<_$OkxPositionImpl> get copyWith =>
      __$$OkxPositionImplCopyWithImpl<_$OkxPositionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OkxPositionImplToJson(this);
  }
}

abstract class _OkxPosition implements OkxPosition {
  const factory _OkxPosition({
    final String instId,
    final String posSide,
    final String pos,
    final String avgPx,
    final String markPx,
    final String lever,
    final String liqPx,
    final String upl,
    final String uplRatio,
    final String mgnMode,
    final String notionalUsd,
    final String instType,
    final String positionId,
    final String signedSize,
    final String size,
    final String direction,
    final String marginCurrency,
    final String positionCurrency,
    final Map<String, dynamic> identity,
    final Map<String, dynamic> eligibleActions,
  }) = _$OkxPositionImpl;

  factory _OkxPosition.fromJson(Map<String, dynamic> json) =
      _$OkxPositionImpl.fromJson;

  @override
  String get instId; // Cặp giao dịch (VD: BTC-USDT-SWAP)
  @override
  String get posSide; // Chiều vị thế (long, short, net)
  @override
  String get pos; // Kích thước vị thế (Số lượng)
  @override
  String get avgPx; // Giá vào lệnh trung bình (Entry Price)
  @override
  String get markPx; // Giá đánh dấu hiện hành (Mark Price)
  @override
  String get lever; // Đòn bẩy hiện tại
  @override
  String get liqPx; // Giá thanh lý ước tính
  @override
  String get upl; // Lãi/lỗ chưa thực hiện (Unrealized PnL - USD)
  @override
  String get uplRatio; // Tỷ lệ Lãi/lỗ
  @override
  String get mgnMode; // Chế độ Margin (cross hoặc isolated)
  @override
  String get notionalUsd; // Giá trị danh nghĩa vị thế theo USD
  @override
  String get instType;
  @override
  String get positionId;
  @override
  String get signedSize;
  @override
  String get size;
  @override
  String get direction;
  @override
  String get marginCurrency;
  @override
  String get positionCurrency;
  @override
  Map<String, dynamic> get identity;
  @override
  Map<String, dynamic> get eligibleActions;

  /// Create a copy of OkxPosition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxPositionImplCopyWith<_$OkxPositionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
