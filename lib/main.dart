// File Name: main.dart
// File Path: lib/main.dart

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
import 'features/portfolio/presentation/portfolio_screen.dart'
    show hideBalanceProvider;
import 'features/settings/presentation/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // BẢO VỆ 1: Chỉ khởi tạo Background Service nếu KHÔNG PHẢI là Web
  if (!kIsWeb) {
    try {
      await initializeBackgroundService();
    } catch (e) {
      debugPrint('Lỗi khởi tạo Background Service: $e');
    }
  }

  // BẢO VỆ 2: Khởi tạo Storage an toàn tuyệt đối cho Web
  SecureStorageHelper helper;

  if (kIsWeb) {
    // Nếu là Web, dùng SharedPreferences để lưu trữ bền vững trên LocalStorage của trình duyệt
    final prefs = await SharedPreferences.getInstance();
    helper = WebStorageHelper(prefs);
  } else {
    // Nếu là Mobile, dùng Secure Storage thật
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    helper = SecureStorageHelper(storage);
  }

  // Thiết lập giá trị mặc định
  bool bioAuth = false;
  bool hideBalanceDefault = false;
  String themeModeStr = 'system';
  String currencyStr = 'USD';
  var navigationPreferences = NavigationPreferences.defaults;

  try {
    bioAuth = await helper.getBiometricAuth();
    hideBalanceDefault = await helper.getHideBalanceDefault();
    themeModeStr = await helper.getThemeMode();
    currencyStr = await helper.getCurrency();
  } catch (e) {
    debugPrint('Bỏ qua lỗi đọc Storage: $e');
  }

  // Keep this read independent from legacy preferences. A failed theme or
  // credential read must not prevent navigation from rendering its saved mode.
  try {
    navigationPreferences = await helper.getNavigationPreferences();
  } catch (e) {
    debugPrint('Bỏ qua lỗi đọc tùy chọn điều hướng: $e');
  }

  final initialThemeMode = themeModeStr == 'dark'
      ? ThemeMode.dark
      : (themeModeStr == 'light' ? ThemeMode.light : ThemeMode.system);

  runApp(
    ProviderScope(
      overrides: [
        // QUAN TRỌNG: Ép toàn bộ các module khác (OKX Interceptor, Settings) phải dùng chung bản Mock Helper này trên Web
        secureStorageProvider.overrideWithValue(helper),

        hideBalanceProvider.overrideWith((ref) => hideBalanceDefault),
        themeModeProvider.overrideWith((ref) => initialThemeMode),
        currencyProvider.overrideWith((ref) => currencyStr),
        navigationPreferencesInitialProvider.overrideWithValue(
          navigationPreferences,
        ),
      ],
      // Nếu là Web, luôn vào thẳng Portfolio (bỏ qua sinh trắc học)
      child: TradingBalanceApp(requireBiometrics: kIsWeb ? false : bioAuth),
    ),
  );
}

class TradingBalanceApp extends StatelessWidget {
  final bool requireBiometrics;

  const TradingBalanceApp({super.key, required this.requireBiometrics});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto Portfolio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: requireBiometrics
          ? const BiometricAuthScreen()
          : const MainNavigationShell(),
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
    if (_isAuthenticated) {
      return const MainNavigationShell();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _isChecking
            ? const CircularProgressIndicator(color: Colors.black)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 80, color: Colors.black),
                  const SizedBox(height: 24),
                  const Text(
                    'Ứng dụng đã bị khoá',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vui lòng xác thực để bảo vệ tài sản',
                    style: TextStyle(color: Colors.grey),
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
                        style: const TextStyle(
                          color: Colors.redAccent,
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
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
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
