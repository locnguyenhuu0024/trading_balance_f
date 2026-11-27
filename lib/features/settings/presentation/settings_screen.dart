// File Name: settings_screen.dart
// File Path: lib/features/settings/presentation/settings_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/backend_features.dart';
import '../../../core/currency/coingecko_vnd_rate_client.dart';
import '../../../core/currency/currency_display_mode.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/timezone/app_time_zone.dart';
import '../../../core/typography/app_text_scale.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../../core/widgets/responsive_form_content.dart';
import '../../../core/widgets/scope_bar.dart';
import '../../avatar/domain/avatar_display.dart';
import '../../avatar/domain/avatar_model.dart';
import '../../fractal_tracker/presentation/providers/fractal_provider.dart';
import '../../portfolio/presentation/portfolio_screen.dart';
import 'settings_avatar_model_page.dart';
import 'settings_trade_access_page.dart';

// --- Các Provider quản lý cấu hình toàn cục ---
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final currencyProvider = StateProvider<String>((ref) => 'USD');
final defaultHideBalanceProvider = StateProvider<bool>((ref) => false);
final avatarEnabledProvider = StateProvider<bool>((ref) => false);
final biometricAuthProvider = StateProvider<bool>((ref) => true);

final _avatarFramingSavingProvider = StateProvider<bool>((ref) => false);

final _avatarScaleSaverProvider = Provider<_AvatarScaleSaver>(
  (ref) => _AvatarScaleSaver(
    ref.watch(secureStorageProvider),
    ref.read(avatarScalePercentProvider.notifier),
  ),
);

void _showAvatarSaveError(ScaffoldMessengerState messenger) {
  if (messenger.mounted) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Không lưu được cài đặt')),
    );
  }
}

// Keep the last persisted value and queued writes across Settings visits.
class _AvatarScaleSaver {
  _AvatarScaleSaver(this._storage, this._scale) : _persisted = _scale.state;

  final SecureStorageHelper _storage;
  final StateController<int> _scale;
  int _persisted;
  bool _saving = false;
  ({int percent, ScaffoldMessengerState messenger})? _pending;

  Future<void> save(int percent, ScaffoldMessengerState messenger) async {
    _pending = (percent: percent, messenger: messenger);
    if (_saving) return;
    _saving = true;
    try {
      while (_pending != null) {
        final request = _pending!;
        _pending = null;
        try {
          await _storage.saveAvatarScale(request.percent);
          _persisted = request.percent;
        } catch (_) {
          if (_scale.mounted &&
              _scale.state == request.percent &&
              _pending?.percent != request.percent) {
            _scale.state = _persisted;
          }
          _showAvatarSaveError(request.messenger);
        }
      }
    } finally {
      _saving = false;
    }
  }
}

// --- Provider lấy tỷ giá ---
final vndExchangeRateProvider = FutureProvider<double>((ref) async {
  try {
    return await ref.watch(coinGeckoVndRateClientProvider).fetchVndRate();
  } on Object {
    return 25400.0;
  }
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _timeZoneDescription =
      'Áp dụng cho toàn bộ mốc thời gian trong ứng dụng.';

  bool _isSavingAvatar = false;
  bool _hasUserChangedAvatar = false;
  bool _isSavingTimeZone = false;
  bool _isSavingAppTextScale = false;
  bool _hasUserChangedAppTextScale = false;
  bool _isRefreshingExchangeRate = false;

  Future<void> _refreshExchangeRate() async {
    if (_isRefreshingExchangeRate) return;
    setState(() => _isRefreshingExchangeRate = true);
    try {
      ref.invalidate(vndExchangeRateProvider);
      await ref.read(vndExchangeRateProvider.future);
    } catch (_) {
      // The exchange-rate provider keeps its local fallback available.
    } finally {
      if (mounted) setState(() => _isRefreshingExchangeRate = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
  }

  Future<void> _loadSavedPreferences() async {
    final storage = ref.read(secureStorageProvider);
    unawaited(_loadSavedAvatarModel(storage));
    final hideBalance = await storage.getHideBalanceDefault();
    final bioAuth = await storage.getBiometricAuth();
    final themeModeStr = await storage.getThemeMode();
    final currency = await storage.getCurrency();
    final timeZoneId = await storage.getTimeZoneId();
    var appTextScale = AppTextScale.defaultScale;
    try {
      appTextScale = await storage.getAppTextScale();
    } catch (_) {
      // Keep the current/root scale when the optional setting cannot be read.
    }

    if (mounted) {
      // Khôi phục trạng thái lên UI
      ref.read(defaultHideBalanceProvider.notifier).state = hideBalance;
      ref.read(biometricAuthProvider.notifier).state = bioAuth;
      ref.read(themeModeProvider.notifier).state = themeModeStr == 'dark'
          ? ThemeMode.dark
          : (themeModeStr == 'light' ? ThemeMode.light : ThemeMode.system);
      ref.read(currencyProvider.notifier).state = currency;
      ref.read(appTimeZoneProvider.notifier).state = AppTimeZone.normalizeId(
        timeZoneId,
      );
      if (!_hasUserChangedAppTextScale) {
        ref.read(appTextScaleProvider.notifier).state = appTextScale;
      }
    }

    var avatarEnabled = false;
    try {
      avatarEnabled = await storage.getAvatarEnabled();
    } catch (_) {
      // Use the default when the preference cannot be read.
    }
    if (mounted && !_hasUserChangedAvatar) {
      ref.read(avatarEnabledProvider.notifier).state = avatarEnabled;
    }
  }

  Future<void> _loadSavedAvatarModel(SecureStorageHelper storage) async {
    var selectionChanged = false;
    final subscription = ref.listenManual(
      avatarModelIdProvider,
      (_, _) => selectionChanged = true,
    );

    var modelId = defaultAvatarModelId;
    try {
      modelId = avatarModelById(await storage.getAvatarModelId()).id;
    } catch (_) {
      // Use the default when the preference cannot be read.
    } finally {
      if (mounted) subscription.close();
    }

    if (mounted && !selectionChanged) {
      ref.read(avatarModelIdProvider.notifier).state = modelId;
    }
  }

  Future<void> _saveAvatarEnabled(bool enabled) async {
    if (_isSavingAvatar) return;

    final storage = ref.read(secureStorageProvider);
    final notifier = ref.read(avatarEnabledProvider.notifier);
    final previousValue = notifier.state;
    _hasUserChangedAvatar = true;
    notifier.state = enabled;
    setState(() => _isSavingAvatar = true);
    try {
      await storage.saveAvatarEnabled(enabled);
    } catch (_) {
      if (notifier.mounted) notifier.state = previousValue;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Không lưu được cài đặt')));
      }
    } finally {
      if (mounted) setState(() => _isSavingAvatar = false);
    }
  }

  Future<void> _saveAvatarFraming(AvatarFraming framing) async {
    final saving = ref.read(_avatarFramingSavingProvider.notifier);
    if (saving.state) return;
    final selection = ref.read(avatarFramingProvider.notifier);
    final previous = selection.state;
    if (previous == framing) return;

    final storage = ref.read(secureStorageProvider);
    final messenger = ScaffoldMessenger.of(context);
    selection.state = framing;
    saving.state = true;
    try {
      await storage.saveAvatarFraming(framing.wireName);
    } catch (_) {
      if (selection.mounted && selection.state == framing) {
        selection.state = previous;
      }
      _showAvatarSaveError(messenger);
    } finally {
      if (saving.mounted) saving.state = false;
    }
  }

  // --- Hàm tiện ích để lưu toàn bộ App Preferences ---
  Future<void> _saveAllPreferences() async {
    final storage = ref.read(secureStorageProvider);
    await storage.saveAppPreferences(
      hideBalance: ref.read(defaultHideBalanceProvider),
      bioAuth: ref.read(biometricAuthProvider),
      themeMode: ref.read(themeModeProvider).name,
      currency: ref.read(currencyProvider),
    );
  }

  Future<void> _saveTimeZone(String timeZoneId) async {
    if (_isSavingTimeZone) return;

    final normalizedTimeZoneId = AppTimeZone.normalizeId(timeZoneId);
    final previousTimeZoneId = ref.read(appTimeZoneProvider);
    if (normalizedTimeZoneId == previousTimeZoneId) return;

    ref.read(appTimeZoneProvider.notifier).state = normalizedTimeZoneId;
    setState(() => _isSavingTimeZone = true);

    try {
      await ref
          .read(secureStorageProvider)
          .saveTimeZoneId(normalizedTimeZoneId);
      ref.invalidate(fractalDataProvider);
    } catch (_) {
      if (mounted) {
        ref.read(appTimeZoneProvider.notifier).state = previousTimeZoneId;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Không lưu được múi giờ. Vui lòng thử lại.'),
            backgroundColor: AppPalette.of(context).negative,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingTimeZone = false);
    }
  }

  Future<void> _saveAppTextScale(double scale) async {
    if (_isSavingAppTextScale) return;

    final normalizedScale = AppTextScale.normalize(scale);
    final previousScale = ref.read(appTextScaleProvider);
    if (normalizedScale == previousScale) return;

    _hasUserChangedAppTextScale = true;
    ref.read(appTextScaleProvider.notifier).state = normalizedScale;
    setState(() => _isSavingAppTextScale = true);

    try {
      await ref.read(secureStorageProvider).saveAppTextScale(normalizedScale);
    } catch (_) {
      if (mounted) {
        ref.read(appTextScaleProvider.notifier).state = previousScale;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Không lưu được cỡ chữ ứng dụng. Vui lòng thử lại.',
            ),
            backgroundColor: AppPalette.of(context).negative,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingAppTextScale = false);
    }
  }

  void _showTimeZoneInfo() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Múi giờ'),
        content: const ResponsiveFormContent(
          maxWidth: 560,
          padding: EdgeInsets.zero,
          child: Text(_timeZoneDescription),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeZoneTile({
    required String timeZoneId,
    required Color textColor,
    required Color cardColor,
    required Color sectionTitleColor,
    required bool compact,
  }) {
    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: const Key('settings-timezone-select'),
        isExpanded: compact,
        value: AppTimeZone.normalizeId(timeZoneId),
        dropdownColor: cardColor,
        icon: Icon(
          Icons.unfold_more_rounded,
          color: sectionTitleColor,
          size: 20,
        ),
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        alignment: AlignmentDirectional.centerEnd,
        items: AppTimeZone.options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.id,
                child: Text(
                  '${option.label} (${option.id})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _isSavingTimeZone
            ? null
            : (String? value) {
                if (value != null) _saveTimeZone(value);
              },
      ),
    );

    return ListTile(
      contentPadding: compact ? EdgeInsets.zero : null,
      minLeadingWidth: compact ? 28 : null,
      horizontalTitleGap: compact ? 8 : null,
      leading: Icon(Icons.schedule_outlined, color: textColor, size: 22),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Múi giờ',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          IconButton(
            key: const Key('settings-timezone-info-button'),
            tooltip: 'Thông tin múi giờ',
            visualDensity: VisualDensity.standard,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: AppTokens.minimumTouchTarget,
              minHeight: AppTokens.minimumTouchTarget,
            ),
            icon: Icon(
              Icons.help_outline_rounded,
              color: sectionTitleColor,
              size: 18,
            ),
            onPressed: _showTimeZoneInfo,
          ),
        ],
      ),
      subtitle: compact ? dropdown : null,
      trailing: compact ? null : dropdown,
    );
  }

  Widget _buildAvatarDisplaySettings(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    final framing = ref.watch(avatarFramingProvider);
    final framingSaving = ref.watch(_avatarFramingSavingProvider);
    final scale = ref.watch(avatarScalePercentProvider);
    final scaleSaver = ref.watch(_avatarScaleSaverProvider);
    final scaleLabel = '$scale%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Khung hình'),
          const SizedBox(height: 4),
          SegmentedButton<AvatarFraming>(
            key: const Key('settings-avatar-framing'),
            expandedInsets: EdgeInsets.zero,
            style: const ButtonStyle(
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            segments: [
              for (final option in AvatarFraming.values)
                ButtonSegment(
                  value: option,
                  label: Text(option.label, textAlign: TextAlign.center),
                ),
            ],
            selected: {framing},
            onSelectionChanged: enabled && !framingSaving
                ? (selected) => _saveAvatarFraming(selected.single)
                : null,
          ),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: Row(
              children: [
                const Expanded(child: Text('Kích thước nhân vật')),
                Text(scaleLabel),
              ],
            ),
          ),
          Semantics(
            label: 'Kích thước nhân vật',
            child: SizedBox(
              height: AppTokens.minimumTouchTarget,
              child: Slider(
                key: const Key('settings-avatar-scale-slider'),
                min: AvatarScale.min.toDouble(),
                max: AvatarScale.max.toDouble(),
                divisions:
                    (AvatarScale.max - AvatarScale.min) ~/ AvatarScale.step,
                value: scale.toDouble(),
                label: scaleLabel,
                semanticFormatterCallback: (value) => '${value.round()}%',
                onChanged: enabled
                    ? (value) {
                        ref.read(avatarScalePercentProvider.notifier).state =
                            value.round();
                      }
                    : null,
                onChangeEnd: enabled
                    ? (value) => scaleSaver.save(
                        value.round(),
                        ScaffoldMessenger.of(context),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final currency = ref.watch(currencyProvider);
    final exchangeRateAsync = ref.watch(vndExchangeRateProvider);
    final hideBalanceDefault = ref.watch(defaultHideBalanceProvider);
    final bioAuth = ref.watch(biometricAuthProvider);
    final avatarEnabled = ref.watch(avatarEnabledProvider);
    final avatarModel = avatarModelById(ref.watch(avatarModelIdProvider));
    final timeZoneId = ref.watch(appTimeZoneProvider);
    final appTextScale = ref.watch(appTextScaleProvider);
    final backendFeaturesEnabled = ref.watch(backendFeaturesEnabledProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.forBrightness(isDark);
    final bgColor = palette.background;
    final textColor = palette.ink;
    final cardColor = palette.raised;
    final sectionTitleColor = palette.muted;
    final compactSettings =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.2;

    final themeModeSelector = DropdownButtonHideUnderline(
      child: DropdownButton<ThemeMode>(
        value: themeMode,
        isExpanded: compactSettings,
        dropdownColor: cardColor,
        icon: Icon(
          Icons.unfold_more_rounded,
          color: sectionTitleColor,
          size: 20,
        ),
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        alignment: AlignmentDirectional.centerEnd,
        items: const [
          DropdownMenuItem(value: ThemeMode.light, child: Text('Sáng')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Tối')),
          DropdownMenuItem(value: ThemeMode.system, child: Text('Hệ thống')),
        ],
        onChanged: (ThemeMode? value) {
          if (value != null) {
            ref.read(themeModeProvider.notifier).state = value;
            _saveAllPreferences();
          }
        },
      ),
    );
    final currencySelector = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: const Key('settings-currency-select'),
        value: currency,
        isExpanded: compactSettings,
        dropdownColor: cardColor,
        icon: Icon(
          Icons.unfold_more_rounded,
          color: sectionTitleColor,
          size: 20,
        ),
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        alignment: AlignmentDirectional.centerEnd,
        items: CurrencyDisplayMode.options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.value,
                child: Text(option.label),
              ),
            )
            .toList(),
        onChanged: (String? value) {
          if (value != null) {
            ref.read(currencyProvider.notifier).state = value;
            _saveAllPreferences();
          }
        },
      ),
    );
    final currencyExchangeRate = CurrencyDisplayMode.includesVnd(currency)
        ? exchangeRateAsync.when(
            data: (rate) => Text(
              '1 USDT ≈ ${NumberFormat("#,##0", "en_US").format(rate)} đ',
              style: TextStyle(
                color: palette.positive,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            loading: () => Text(
              'Đang cập nhật tỷ giá...',
              style: TextStyle(color: sectionTitleColor, fontSize: 12),
            ),
            error: (_, __) => Text(
              'Lỗi tải tỷ giá (Dùng giá chuẩn)',
              style: TextStyle(color: palette.negative, fontSize: 12),
            ),
          )
        : null;
    final appTextScaleSelector = DropdownButtonHideUnderline(
      child: DropdownButton<double>(
        key: const Key('settings-app-text-scale-select'),
        value: appTextScale,
        isExpanded: compactSettings,
        dropdownColor: cardColor,
        icon: Icon(
          Icons.unfold_more_rounded,
          color: sectionTitleColor,
          size: 20,
        ),
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        alignment: AlignmentDirectional.centerEnd,
        items: AppTextScale.options
            .map(
              (option) => DropdownMenuItem<double>(
                value: option.value,
                child: Text(option.label),
              ),
            )
            .toList(),
        onChanged: _isSavingAppTextScale
            ? null
            : (double? value) {
                if (value != null) _saveAppTextScale(value);
              },
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: NavigationContentFrame(
          child: AppEntranceScope(
            child: SingleChildScrollView(
              child: ResponsiveFormContent(
                maxWidth: 960,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (Navigator.of(context).canPop()) const BackButton(),
                        const Expanded(
                          child: Text(
                            'Cài đặt',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(child: ScopeBar(compact: true)),
                        ManualRefreshButton(
                          buttonKey: const Key('settings-manual-refresh'),
                          onRefresh: _refreshExchangeRate,
                          isBusy:
                              _isRefreshingExchangeRate ||
                              exchangeRateAsync.isLoading,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // ================= SECTION 1: GIAO DIỆN =================
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        'HIỂN THỊ & GIAO DIỆN',
                        style: TextStyle(
                          color: sectionTitleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AppEntrance(
                      index: 0,
                      child: Card(
                        elevation: 0,
                        color: cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: palette.border),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.dark_mode_outlined,
                                color: textColor,
                                size: 22,
                              ),
                              title: Text(
                                'Chế độ nền',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: compactSettings
                                  ? themeModeSelector
                                  : null,
                              trailing: compactSettings
                                  ? null
                                  : themeModeSelector,
                            ),
                            Divider(
                              height: 1,
                              color: palette.border,
                              indent: 52,
                            ),
                            _buildTimeZoneTile(
                              timeZoneId: timeZoneId,
                              textColor: textColor,
                              cardColor: cardColor,
                              sectionTitleColor: sectionTitleColor,
                              compact: compactSettings,
                            ),
                            Divider(
                              height: 1,
                              color: isDark ? palette.border : palette.surface,
                              indent: 52,
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.attach_money_rounded,
                                color: textColor,
                                size: 22,
                              ),
                              title: Text(
                                'Tiền tệ hiển thị',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: compactSettings
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        currencySelector,
                                        if (currencyExchangeRate != null)
                                          currencyExchangeRate,
                                      ],
                                    )
                                  : currencyExchangeRate,
                              trailing: compactSettings
                                  ? null
                                  : currencySelector,
                            ),
                            Divider(
                              height: 1,
                              color: isDark ? palette.border : palette.surface,
                              indent: 52,
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.text_fields_rounded,
                                color: textColor,
                                size: 22,
                              ),
                              title: Text(
                                'Cỡ chữ ứng dụng',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: compactSettings
                                  ? appTextScaleSelector
                                  : null,
                              trailing: compactSettings
                                  ? null
                                  : appTextScaleSelector,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ================= SECTION 2: BẢO MẬT & TRẢI NGHIỆM =================
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        'BẢO MẬT & TRẢI NGHIỆM',
                        style: TextStyle(
                          color: sectionTitleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AppEntrance(
                      index: 1,
                      child: Card(
                        elevation: 0,
                        color: cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: palette.border),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              secondary: Icon(
                                Icons.visibility_off,
                                color: textColor,
                                size: 22,
                              ),
                              title: Text(
                                'Ẩn số dư mặc định',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                'Che tài sản khi vừa mở ứng dụng',
                                style: TextStyle(
                                  color: sectionTitleColor,
                                  fontSize: 12,
                                ),
                              ),
                              value: hideBalanceDefault,
                              onChanged: (val) {
                                ref
                                        .read(
                                          defaultHideBalanceProvider.notifier,
                                        )
                                        .state =
                                    val;
                                ref.read(hideBalanceProvider.notifier).state =
                                    val; // Cập nhật luôn màn chính
                                _saveAllPreferences();
                              },
                            ),
                            Divider(
                              height: 1,
                              color: isDark ? palette.border : palette.surface,
                              indent: 52,
                            ),
                            SwitchListTile(
                              key: const Key('settings-avatar-switch'),
                              secondary: Icon(
                                Icons.view_in_ar,
                                color: textColor,
                                size: 22,
                              ),
                              title: Text(
                                'Nhân vật 3D',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                'Hiển thị nhân vật biểu cảm theo lãi/lỗ',
                                style: TextStyle(
                                  color: sectionTitleColor,
                                  fontSize: 12,
                                ),
                              ),
                              value: avatarEnabled,
                              onChanged: _isSavingAvatar
                                  ? null
                                  : _saveAvatarEnabled,
                            ),
                            ListTile(
                              key: const Key('settings-avatar-model-button'),
                              title: const Text('Chọn nhân vật'),
                              subtitle: Text(avatarModel.name),
                              trailing: const Icon(Icons.chevron_right),
                              enabled: avatarEnabled,
                              onTap: avatarEnabled
                                  ? () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const SettingsAvatarModelPage(),
                                      ),
                                    )
                                  : null,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
                              child: Text(
                                avatarModel.credit,
                                key: const Key('settings-avatar-credit'),
                                style: TextStyle(
                                  color: sectionTitleColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Consumer(
                              builder: (context, ref, _) =>
                                  _buildAvatarDisplaySettings(
                                    context,
                                    ref,
                                    avatarEnabled,
                                  ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark ? palette.border : palette.surface,
                              indent: 52,
                            ),
                            SwitchListTile(
                              secondary: Icon(
                                Icons.fingerprint,
                                color: textColor,
                                size: 22,
                              ),
                              title: Text(
                                'Khoá sinh trắc học',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                'Yêu cầu vân tay / FaceID khi mở app',
                                style: TextStyle(
                                  color: sectionTitleColor,
                                  fontSize: 12,
                                ),
                              ),
                              value: bioAuth,
                              onChanged: (val) {
                                ref.read(biometricAuthProvider.notifier).state =
                                    val;
                                _saveAllPreferences();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (backendFeaturesEnabled)
                      AppEntrance(
                        index: 2,
                        child: Card(
                          elevation: 0,
                          color: cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: palette.border),
                          ),
                          child: ListTile(
                            key: const Key('settings-trade-access-button'),
                            leading: Icon(Icons.key_rounded, color: textColor),
                            title: Text(
                              'API và giao dịch',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Cấu hình khóa OKX và quản lý phiên giao dịch',
                              style: TextStyle(
                                color: sectionTitleColor,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: sectionTitleColor,
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const SettingsTradeAccessPage(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
