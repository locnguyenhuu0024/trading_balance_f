import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../../orders/presentation/widgets/trade_account_controls.dart';

class SettingsTradeAccessPage extends ConsumerStatefulWidget {
  const SettingsTradeAccessPage({super.key});

  @override
  ConsumerState<SettingsTradeAccessPage> createState() =>
      _SettingsTradeAccessPageState();
}

class _SettingsTradeAccessPageState
    extends ConsumerState<SettingsTradeAccessPage> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSavedKeys();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedKeys() async {
    final storage = ref.read(secureStorageProvider);
    final apiKey = await storage.getOkxApiKey();
    final secretKey = await storage.getOkxSecretKey();
    final passphrase = await storage.getOkxPassphrase();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = apiKey ?? '';
      _secretKeyController.text = secretKey ?? '';
      _passphraseController.text = passphrase ?? '';
    });
  }

  Future<void> _saveKeys() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(secureStorageProvider)
          .saveOkxCredentials(
            apiKey: _apiKeyController.text.trim(),
            secretKey: _secretKeyController.text.trim(),
            passphrase: _passphraseController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu cấu hình API thành công!'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('API và giao dịch')),
      body: NavigationContentFrame(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                'CẤU HÌNH API (CHỈ ĐỌC)',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Thông tin API được mã hóa cục bộ trên thiết bị của bạn, không gửi qua máy chủ trung gian.',
                        style: TextStyle(color: mutedColor, fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      _credentialField(
                        controller: _apiKeyController,
                        label: 'API Key',
                        icon: Icons.key,
                      ),
                      const SizedBox(height: 16),
                      _credentialField(
                        controller: _secretKeyController,
                        label: 'Secret Key',
                        icon: Icons.security,
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      _credentialField(
                        controller: _passphraseController,
                        label: 'Passphrase',
                        icon: Icons.lock,
                        obscureText: true,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('settings-save-okx-credentials'),
                        onPressed: _isSaving ? null : _saveKeys,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Lưu cấu hình'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const TradeSessionControls(),
          ],
        ),
      ),
    );
  }

  Widget _credentialField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'Không được để trống' : null,
    );
  }
}
