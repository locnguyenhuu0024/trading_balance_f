// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'okx_ticker_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

OkxTickerModel _$OkxTickerModelFromJson(Map<String, dynamic> json) {
  return _OkxTickerModel.fromJson(json);
}

/// @nodoc
mixin _$OkxTickerModel {
  String get instId =>
      throw _privateConstructorUsedError; // Cặp giao dịch (VD: BTC-USDT)
  String get last => throw _privateConstructorUsedError;

  /// Serializes this OkxTickerModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OkxTickerModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OkxTickerModelCopyWith<OkxTickerModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OkxTickerModelCopyWith<$Res> {
  factory $OkxTickerModelCopyWith(
    OkxTickerModel value,
    $Res Function(OkxTickerModel) then,
  ) = _$OkxTickerModelCopyWithImpl<$Res, OkxTickerModel>;
  @useResult
  $Res call({String instId, String last});
}

/// @nodoc
class _$OkxTickerModelCopyWithImpl<$Res, $Val extends OkxTickerModel>
    implements $OkxTickerModelCopyWith<$Res> {
  _$OkxTickerModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OkxTickerModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? instId = null, Object? last = null}) {
    return _then(
      _value.copyWith(
            instId: null == instId
                ? _value.instId
                : instId // ignore: cast_nullable_to_non_nullable
                      as String,
            last: null == last
                ? _value.last
                : last // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OkxTickerModelImplCopyWith<$Res>
    implements $OkxTickerModelCopyWith<$Res> {
  factory _$$OkxTickerModelImplCopyWith(
    _$OkxTickerModelImpl value,
    $Res Function(_$OkxTickerModelImpl) then,
  ) = __$$OkxTickerModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String instId, String last});
}

/// @nodoc
class __$$OkxTickerModelImplCopyWithImpl<$Res>
    extends _$OkxTickerModelCopyWithImpl<$Res, _$OkxTickerModelImpl>
    implements _$$OkxTickerModelImplCopyWith<$Res> {
  __$$OkxTickerModelImplCopyWithImpl(
    _$OkxTickerModelImpl _value,
    $Res Function(_$OkxTickerModelImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OkxTickerModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? instId = null, Object? last = null}) {
    return _then(
      _$OkxTickerModelImpl(
        instId: null == instId
            ? _value.instId
            : instId // ignore: cast_nullable_to_non_nullable
                  as String,
        last: null == last
            ? _value.last
            : last // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OkxTickerModelImpl implements _OkxTickerModel {
  const _$OkxTickerModelImpl({this.instId = '', this.last = '0'});

  factory _$OkxTickerModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$OkxTickerModelImplFromJson(json);

  @override
  @JsonKey()
  final String instId;
  // Cặp giao dịch (VD: BTC-USDT)
  @override
  @JsonKey()
  final String last;

  @override
  String toString() {
    return 'OkxTickerModel(instId: $instId, last: $last)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OkxTickerModelImpl &&
            (identical(other.instId, instId) || other.instId == instId) &&
            (identical(other.last, last) || other.last == last));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, instId, last);

  /// Create a copy of OkxTickerModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OkxTickerModelImplCopyWith<_$OkxTickerModelImpl> get copyWith =>
      __$$OkxTickerModelImplCopyWithImpl<_$OkxTickerModelImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$OkxTickerModelImplToJson(this);
  }
}

abstract class _OkxTickerModel implements OkxTickerModel {
  const factory _OkxTickerModel({final String instId, final String last}) =
      _$OkxTickerModelImpl;

  factory _OkxTickerModel.fromJson(Map<String, dynamic> json) =
      _$OkxTickerModelImpl.fromJson;

  @override
  String get instId; // Cặp giao dịch (VD: BTC-USDT)
  @override
  String get last;

  /// Create a copy of OkxTickerModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OkxTickerModelImplCopyWith<_$OkxTickerModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
