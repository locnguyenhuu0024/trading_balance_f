// File Name: main.dart
// File Path: lib/main.dart

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Dùng kIsWeb
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/navigation/main_navigation_shell.dart';
import 'core/navigation/navigation_preferences.dart';
import 'core/navigation/navigation_preferences_provider.dart';
import 'core/security/secure_storage_helper.dart';
import 'core/services/background_service.dart';
import 'core/theme/app_theme.dart';
import 'core/timezone/app_time_zone.dart';
import 'core/typography/app_text_scale.dart';
import 'core/widgets/app_page_transition.dart';
import 'core/widgets/app_startup.dart';
import 'features/portfolio/presentation/portfolio_screen.dart'
    show hideBalanceProvider;
import 'features/settings/presentation/settings_screen.dart';

@immutable
class AppStartupData {
  const AppStartupData({
    required this.secureStorage,
    required this.requireBiometrics,
    required this.hideBalanceDefault,
    required this.themeMode,
    required this.currency,
    required this.timeZoneId,
    required this.appTextScale,
    required this.navigationPreferences,
  });

  final SecureStorageHelper secureStorage;
  final bool requireBiometrics;
  final bool hideBalanceDefault;
  final ThemeMode themeMode;
  final String currency;
  final String timeZoneId;
  final double appTextScale;
  final NavigationPreferences navigationPreferences;
}

Future<AppStartupData> initializeAppStartup({
  bool isWeb = kIsWeb,
  Future<SharedPreferences> Function()? loadWebPreferences,
  SecureStorageHelper Function()? createNativeStorage,
  void Function()? initializeTimeZone,
  Future<void> Function()? retireLegacyBackgroundService,
}) async {
  try {
    (initializeTimeZone ?? AppTimeZone.initialize)();
  } catch (_) {
    debugPrint('Time-zone initialization failed; using the UTC fallback.');
  }

  // Retire the legacy background service before restoring app preferences.
  if (!isWeb) {
    try {
      await (retireLegacyBackgroundService ?? retireBackgroundService)();
    } catch (_) {
      debugPrint('Could not retire the legacy background service.');
    }
  }

  SecureStorageHelper helper;

  if (isWeb) {
    final prefs = await (loadWebPreferences ?? SharedPreferences.getInstance)();
    helper = WebStorageHelper(prefs);
  } else {
    helper = (createNativeStorage ?? _createNativeSecureStorage)();
  }

  bool bioAuth = false;
  bool hideBalanceDefault = false;
  String themeModeStr = 'system';
  String currencyStr = 'USD';
  String timeZoneId = AppTimeZone.defaultId;
  var appTextScale = AppTextScale.defaultScale;
  var navigationPreferences = NavigationPreferences.defaults;

  try {
    bioAuth = await helper.getBiometricAuth();
    hideBalanceDefault = await helper.getHideBalanceDefault();
    themeModeStr = await helper.getThemeMode();
    currencyStr = await helper.getCurrency();
    timeZoneId = await helper.getTimeZoneId();
  } catch (_) {
    debugPrint('Legacy preference restoration failed; using safe defaults.');
  }

  try {
    appTextScale = await helper.getAppTextScale();
  } catch (_) {
    debugPrint('App text-scale restoration failed; using the default.');
  }

  try {
    navigationPreferences = await helper.getNavigationPreferences();
  } catch (_) {
    debugPrint('Navigation preference restoration failed; using defaults.');
  }

  final initialThemeMode = themeModeStr == 'dark'
      ? ThemeMode.dark
      : (themeModeStr == 'light' ? ThemeMode.light : ThemeMode.system);
  final initialTimeZoneId = AppTimeZone.normalizeId(timeZoneId);

  return AppStartupData(
    secureStorage: helper,
    requireBiometrics: isWeb ? false : bioAuth,
    hideBalanceDefault: hideBalanceDefault,
    themeMode: initialThemeMode,
    currency: currencyStr,
    timeZoneId: initialTimeZoneId,
    appTextScale: appTextScale,
    navigationPreferences: navigationPreferences,
  );
}

SecureStorageHelper _createNativeSecureStorage() {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  return SecureStorageHelper(storage);
}

Widget buildInitializedApp(AppStartupData startup, {Widget? home}) {
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(startup.secureStorage),
      hideBalanceProvider.overrideWith((ref) => startup.hideBalanceDefault),
      themeModeProvider.overrideWith((ref) => startup.themeMode),
      currencyProvider.overrideWith((ref) => startup.currency),
      appTimeZoneProvider.overrideWith((ref) => startup.timeZoneId),
      appTextScaleProvider.overrideWith((ref) => startup.appTextScale),
      navigationPreferencesInitialProvider.overrideWithValue(
        startup.navigationPreferences,
      ),
    ],
    child: TradingBalanceApp(
      requireBiometrics: startup.requireBiometrics,
      home: home,
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    AppStartup<AppStartupData>(
      initialize: initializeAppStartup,
      builder: (context, startup) => buildInitializedApp(startup),
    ),
  );
}

class TradingBalanceApp extends ConsumerWidget {
  final bool requireBiometrics;
  final Widget? home;

  const TradingBalanceApp({
    super.key,
    required this.requireBiometrics,
    this.home,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTextScale = ref.watch(appTextScaleProvider);

    return MaterialApp(
      title: 'Crypto Portfolio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light.copyWith(
        pageTransitionsTheme: AppPageTransitions.theme,
      ),
      darkTheme: AppTheme.dark.copyWith(
        pageTransitionsTheme: AppPageTransitions.theme,
      ),
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) {
        final mediaQuery = MediaQuery.maybeOf(context);
        final appChild = child ?? const SizedBox.shrink();
        if (mediaQuery == null) return appChild;

        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: AppTextScale.combine(
              mediaQuery.textScaler,
              appTextScale,
            ),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            child: appChild,
          ),
        );
      },
      home:
          home ??
          (requireBiometrics
              ? const BiometricAuthScreen()
              : const MainNavigationShell()),
    );
  }
}

class BiometricAuthScreen extends StatefulWidget {
  const BiometricAuthScreen({super.key});

  @override
  State<BiometricAuthScreen> createState() => _BiometricAuthScreenState();
}

class _BiometricAuthScreenState extends State<BiometricAuthScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _isChecking = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _authenticate() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    bool authenticated = false;
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (!canAuthenticate) {
        setState(() {
          _isAuthenticated = true;
          _isChecking = false;
        });
        return;
      }

      authenticated = await auth.authenticate(
        localizedReason: 'Quét vân tay / FaceID để mở khoá OKX Tracker',
      );
    } on PlatformException catch (e) {
      authenticated = false;
      _errorMessage = 'Lỗi hệ thống: ${e.code}\n${e.message}';
    } catch (e) {
      authenticated = false;
      _errorMessage = 'Lỗi không xác định: $e';
    }

    if (mounted) {
      setState(() {
        _isAuthenticated = authenticated;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (_isAuthenticated) {
      return const MainNavigationShell();
    }

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.space4),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: _isChecking
                    ? CircularProgressIndicator(color: palette.ink)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 80,
                            color: palette.ink,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Ứng dụng đã bị khoá',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Vui lòng xác thực để bảo vệ tài sản',
                            style: TextStyle(color: palette.muted),
                          ),
                          const SizedBox(height: 32),

                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: 24,
                                left: 32,
                                right: 32,
                              ),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.warning,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                          ElevatedButton.icon(
                            onPressed: _authenticate,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text(
                              'Mở khoá',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: palette.ink,
                              foregroundColor: palette.onStrong,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
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

// ============================================================================
// LỚP LƯU TRỮ TRÊN WEB (DÀNH RIÊNG CHO MÔI TRƯỜNG WEB)
// BỀN VỮNG QUA CÁC LẦN RELOAD BẰNG SHARED_PREFERENCES
// ============================================================================
class WebStorageHelper extends SecureStorageHelper {
  final SharedPreferences _prefs;

  WebStorageHelper(this._prefs) : super(const FlutterSecureStorage());

  @override
  Future<void> saveOkxCredentials({
    required String apiKey,
    required String secretKey,
    required String passphrase,
  }) async {
    await Future.wait([
      _prefs.setString('OKX_API_KEY', apiKey),
      _prefs.setString('OKX_SECRET_KEY', secretKey),
      _prefs.setString('OKX_PASSPHRASE', passphrase),
    ]);
  }

  @override
  Future<bool> getHideBalanceDefault() async =>
      _prefs.getString('HIDE_BALANCE') == 'true';

  @override
  Future<bool> getBiometricAuth() async =>
      _prefs.getString('BIO_AUTH') == 'true';

  @override
  Future<String> getThemeMode() async =>
      _prefs.getString('THEME_MODE') ?? 'system';

  @override
  Future<String> getCurrency() async => _prefs.getString('CURRENCY') ?? 'USD';

  @override
  Future<String> getTimeZoneId() async =>
      AppTimeZone.normalizeId(_prefs.getString('TIME_ZONE_ID'));

  @override
  Future<double> getAppTextScale() async =>
      AppTextScale.normalize(_prefs.getString('APP_TEXT_SCALE'));

  @override
  Future<void> saveTimeZoneId(String timeZoneId) async {
    final didSave = await _prefs.setString(
      'TIME_ZONE_ID',
      AppTimeZone.normalizeId(timeZoneId),
    );
    if (!didSave) {
      throw StateError('Unable to save the time-zone preference on the web.');
    }
  }

  @override
  Future<void> saveAppTextScale(double scale) async {
    final didSave = await _prefs.setString(
      'APP_TEXT_SCALE',
      AppTextScale.normalize(scale).toString(),
    );
    if (!didSave) {
      throw StateError('Không thể lưu cỡ chữ ứng dụng trên Web.');
    }
  }

  @override
  Future<NavigationPreferences> getNavigationPreferences() async {
    return NavigationPreferences.decode(
      _prefs.getString('NAVIGATION_PREFERENCES'),
    );
  }

  @override
  Future<void> saveNavigationPreferences(
    NavigationPreferences preferences,
  ) async {
    final didSave = await _prefs.setString(
      'NAVIGATION_PREFERENCES',
      preferences.encode(),
    );
    if (!didSave) {
      throw StateError('Không thể lưu tùy chọn điều hướng trên Web.');
    }
  }

  @override
  Future<void> saveAppPreferences({
    required bool hideBalance,
    required bool bioAuth,
    required String themeMode,
    required String currency,
  }) async {
    await Future.wait([
      _prefs.setString('HIDE_BALANCE', hideBalance.toString()),
      _prefs.setString('BIO_AUTH', bioAuth.toString()),
      _prefs.setString('THEME_MODE', themeMode),
      _prefs.setString('CURRENCY', currency),
    ]);
  }

  @override
  Future<String?> getOkxApiKey() async => _prefs.getString('OKX_API_KEY');

  @override
  Future<String?> getOkxSecretKey() async => _prefs.getString('OKX_SECRET_KEY');

  @override
  Future<String?> getOkxPassphrase() async =>
      _prefs.getString('OKX_PASSPHRASE');

  @override
  Future<void> clearOkxCredentials() async {
    await Future.wait([
      _prefs.remove('OKX_API_KEY'),
      _prefs.remove('OKX_SECRET_KEY'),
      _prefs.remove('OKX_PASSPHRASE'),
    ]);
  }
}
