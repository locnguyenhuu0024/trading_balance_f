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
  String get notionalUsd => throw _privateConstructorUsedError;

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
  });

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

  @override
  String toString() {
    return 'OkxPosition(instId: $instId, posSide: $posSide, pos: $pos, avgPx: $avgPx, markPx: $markPx, lever: $lever, liqPx: $liqPx, upl: $upl, uplRatio: $uplRatio, mgnMode: $mgnMode, notionalUsd: $notionalUsd)';
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
                other.notionalUsd == notionalUsd));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
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
  );

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
  String get notionalUsd;

  /// Create a copy of OkxPosition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxPositionImplCopyWith<_$OkxPositionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
