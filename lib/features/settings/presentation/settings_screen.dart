// File Name: settings_screen.dart
// File Path: lib/features/settings/presentation/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../../core/currency/currency_display_mode.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/navigation/navigation_preferences.dart';
import '../../../core/navigation/navigation_preferences_provider.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../../portfolio/presentation/portfolio_screen.dart';

// --- Các Provider quản lý cấu hình toàn cục ---
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final currencyProvider = StateProvider<String>((ref) => 'USD');
final defaultHideBalanceProvider = StateProvider<bool>((ref) => false);
final biometricAuthProvider = StateProvider<bool>((ref) => true);
final backgroundServiceProvider = StateProvider<bool>((ref) => false);

// --- Provider lấy tỷ giá ---
final vndExchangeRateProvider = FutureProvider<double>((ref) async {
  try {
    final dio = Dio();
    final response = await dio.get(
      'https://api.coingecko.com/api/v3/simple/price',
      queryParameters: {'ids': 'tether', 'vs_currencies': 'vnd'},
    );
    return (response.data['tether']['vnd'] as num).toDouble();
  } catch (e) {
    return 25400.0;
  }
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedKeys();
  }

  Future<void> _loadSavedKeys() async {
    final storage = ref.read(secureStorageProvider);
    final apiKey = await storage.getOkxApiKey();
    final secretKey = await storage.getOkxSecretKey();
    final passphrase = await storage.getOkxPassphrase();

    // Tải cấu hình
    final hideBalance = await storage.getHideBalanceDefault();
    final bioAuth = await storage.getBiometricAuth();
    final themeModeStr = await storage.getThemeMode();
    final currency = await storage.getCurrency();

    // Kiểm tra xem Background Service có đang chạy không
    final isServiceRunning = await FlutterBackgroundService().isRunning();

    if (mounted) {
      setState(() {
        _apiKeyController.text = apiKey ?? '';
        _secretKeyController.text = secretKey ?? '';
        _passphraseController.text = passphrase ?? '';
      });

      // Khôi phục trạng thái lên UI
      ref.read(defaultHideBalanceProvider.notifier).state = hideBalance;
      ref.read(biometricAuthProvider.notifier).state = bioAuth;
      ref.read(themeModeProvider.notifier).state = themeModeStr == 'dark'
          ? ThemeMode.dark
          : (themeModeStr == 'light' ? ThemeMode.light : ThemeMode.system);
      ref.read(currencyProvider.notifier).state = currency;
      ref.read(backgroundServiceProvider.notifier).state = isServiceRunning;
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

  Future<void> _saveKeys() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final storage = ref.read(secureStorageProvider);
    await storage.saveOkxCredentials(
      apiKey: _apiKeyController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
      passphrase: _passphraseController.text.trim(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu cấu hình API thành công!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final currency = ref.watch(currencyProvider);
    final exchangeRateAsync = ref.watch(vndExchangeRateProvider);
    final hideBalanceDefault = ref.watch(defaultHideBalanceProvider);
    final bioAuth = ref.watch(biometricAuthProvider);
    final navigationState = ref.watch(navigationPreferencesProvider);
    final navigationPreferences = navigationState.preferences;

    final isSysDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && isSysDark);

    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    final textColor = isDark ? Colors.white : Colors.black;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final sectionTitleColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Cài đặt',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      body: NavigationContentFrame(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Card(
                elevation: 0,
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
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
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<ThemeMode>(
                          value: themeMode,
                          dropdownColor: cardColor,
                          icon: Icon(
                            Icons.unfold_more_rounded,
                            color: sectionTitleColor,
                            size: 20,
                          ),
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Sáng'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Tối'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('Hệ thống'),
                            ),
                          ],
                          onChanged: (ThemeMode? val) {
                            if (val != null) {
                              ref.read(themeModeProvider.notifier).state = val;
                              _saveAllPreferences();
                            }
                          },
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade100,
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
                      subtitle: CurrencyDisplayMode.includesVnd(currency)
                          ? exchangeRateAsync.when(
                              data: (rate) => Text(
                                '1 USDT ≈ ${NumberFormat("#,##0", "en_US").format(rate)} đ',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              loading: () => Text(
                                'Đang cập nhật tỷ giá...',
                                style: TextStyle(
                                  color: sectionTitleColor,
                                  fontSize: 11,
                                ),
                              ),
                              error: (_, __) => const Text(
                                'Lỗi tải tỷ giá (Dùng giá chuẩn)',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : null,
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currency,
                          dropdownColor: cardColor,
                          icon: Icon(
                            Icons.unfold_more_rounded,
                            color: sectionTitleColor,
                            size: 20,
                          ),
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
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
                          onChanged: (String? val) {
                            if (val != null) {
                              ref.read(currencyProvider.notifier).state = val;
                              _saveAllPreferences();
                            }
                          },
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade100,
                      indent: 52,
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.space_dashboard_outlined,
                        color: textColor,
                        size: 22,
                      ),
                      title: Text(
                        'Kiểu hiển thị',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Thay đổi được áp dụng và lưu tự động.',
                        style: TextStyle(
                          color: sectionTitleColor,
                          fontSize: 11,
                        ),
                      ),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<NavigationDisplayMode>(
                          key: const Key('settings-navigation-mode-select'),
                          value: navigationPreferences.displayMode,
                          dropdownColor: cardColor,
                          icon: Icon(
                            Icons.unfold_more_rounded,
                            color: sectionTitleColor,
                            size: 20,
                          ),
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          items: const [
                            DropdownMenuItem(
                              value: NavigationDisplayMode.bar,
                              child: Text('Thanh cố định'),
                            ),
                            DropdownMenuItem(
                              value: NavigationDisplayMode.floating,
                              child: Text('Nút nổi'),
                            ),
                          ],
                          onChanged: navigationState.isSaving
                              ? null
                              : (NavigationDisplayMode? value) {
                                  if (value != null) {
                                    ref
                                        .read(
                                          navigationPreferencesProvider
                                              .notifier,
                                        )
                                        .setDisplayMode(value);
                                  }
                                },
                        ),
                      ),
                    ),
                    if (navigationPreferences.displayMode ==
                        NavigationDisplayMode.floating) ...[
                      Divider(
                        height: 1,
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade100,
                        indent: 52,
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.border_outer_rounded,
                          color: textColor,
                          size: 22,
                        ),
                        title: Text(
                          'Vị trí nút nổi',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<NavigationEdge>(
                            key: const Key('settings-floating-edge-select'),
                            value: navigationPreferences.floatingEdge,
                            dropdownColor: cardColor,
                            icon: Icon(
                              Icons.unfold_more_rounded,
                              color: sectionTitleColor,
                              size: 20,
                            ),
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            alignment: AlignmentDirectional.centerEnd,
                            items: const [
                              DropdownMenuItem(
                                value: NavigationEdge.top,
                                child: Text('Trên'),
                              ),
                              DropdownMenuItem(
                                value: NavigationEdge.bottom,
                                child: Text('Dưới'),
                              ),
                              DropdownMenuItem(
                                value: NavigationEdge.left,
                                child: Text('Trái'),
                              ),
                              DropdownMenuItem(
                                value: NavigationEdge.right,
                                child: Text('Phải'),
                              ),
                            ],
                            onChanged: navigationState.isSaving
                                ? null
                                : (NavigationEdge? value) {
                                    if (value != null) {
                                      ref
                                          .read(
                                            navigationPreferencesProvider
                                                .notifier,
                                          )
                                          .setFloatingEdge(value);
                                    }
                                  },
                          ),
                        ),
                      ),
                    ],
                    if (navigationState.errorMessage != null)
                      Padding(
                        key: const Key('settings-navigation-save-error'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          navigationState.errorMessage!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
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
              Card(
                elevation: 0,
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: Colors.blueAccent,
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
                          fontSize: 11,
                        ),
                      ),
                      value: hideBalanceDefault,
                      onChanged: (val) {
                        ref.read(defaultHideBalanceProvider.notifier).state =
                            val;
                        ref.read(hideBalanceProvider.notifier).state =
                            val; // Cập nhật luôn màn chính
                        _saveAllPreferences();
                      },
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade100,
                      indent: 52,
                    ),
                    SwitchListTile(
                      activeColor: Colors.blueAccent,
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
                          fontSize: 11,
                        ),
                      ),
                      value: bioAuth,
                      onChanged: (val) {
                        ref.read(biometricAuthProvider.notifier).state = val;
                        _saveAllPreferences();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ================= SECTION 3: API KEY =================
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  'CẤU HÌNH API (CHỈ ĐỌC)',
                  style: TextStyle(
                    color: sectionTitleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Card(
                elevation: 0,
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Thông tin API được mã hoá cục bộ trên thiết bị của bạn, không gửi qua bất kỳ máy chủ trung gian nào.',
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _apiKeyController,
                          style: TextStyle(color: textColor, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'API Key',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                              fontSize: 13,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            prefixIcon: Icon(
                              Icons.key,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                              size: 20,
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Không được để trống'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _secretKeyController,
                          style: TextStyle(color: textColor, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Secret Key',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                              fontSize: 13,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            prefixIcon: Icon(
                              Icons.security,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                              size: 20,
                            ),
                          ),
                          obscureText: true,
                          validator: (value) => value == null || value.isEmpty
                              ? 'Không được để trống'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passphraseController,
                          style: TextStyle(color: textColor, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Passphrase',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                              fontSize: 13,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            prefixIcon: Icon(
                              Icons.lock,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                              size: 20,
                            ),
                          ),
                          obscureText: true,
                          validator: (value) => value == null || value.isEmpty
                              ? 'Không được để trống'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _saveKeys,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: isDark
                                ? Colors.white
                                : Colors.black,
                            foregroundColor: isDark
                                ? Colors.black
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Lưu cấu hình',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
