import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../orders/presentation/widgets/trade_account_controls.dart';
import '../domain/okx_credential_bundle.dart';

class SettingsTradeAccessPage extends ConsumerStatefulWidget {
  const SettingsTradeAccessPage({super.key});

  @override
  ConsumerState<SettingsTradeAccessPage> createState() =>
      _SettingsTradeAccessPageState();
}

class _SettingsTradeAccessPageState
    extends ConsumerState<SettingsTradeAccessPage> {
  final _formKey = GlobalKey<FormState>();
  final _bundleController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPastingFromClipboard = false;
  bool _hasCompleteSavedCredentials = false;
  bool _isEditing = true;
  bool _isManualEntry = false;
  int _credentialUiGeneration = 0;
  String? _loadError;
  String? _saveError;

  bool get _inputsEnabled =>
      !_isLoading &&
      !_isSaving &&
      !_isPastingFromClipboard &&
      _loadError == null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedKeys());
  }

  @override
  void dispose() {
    _bundleController.dispose();
    _apiKeyController.dispose();
    _secretKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedKeys() async {
    try {
      final storage = ref.read(secureStorageProvider);
      final values = await Future.wait([
        storage.getOkxApiKey(),
        storage.getOkxSecretKey(),
        storage.getOkxPassphrase(),
      ]);
      if (!mounted) return;

      final hasAllValues = values.every(
        (value) => value != null && value.trim().isNotEmpty,
      );
      setState(() {
        _isLoading = false;
        _loadError = null;
        _hasCompleteSavedCredentials = hasAllValues;
        _isEditing = !hasAllValues;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasCompleteSavedCredentials = false;
        _isEditing = true;
        _loadError = 'Không thể tải thông tin API đã lưu. Hãy thử lại.';
      });
    }
  }

  void _retryLoad() {
    if (_isLoading || _isSaving) return;
    _credentialUiGeneration++;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _saveError = null;
    });
    unawaited(_loadSavedKeys());
  }

  void _beginReplacement() {
    if (_isSaving || !_hasCompleteSavedCredentials) return;
    _credentialUiGeneration++;
    setState(() {
      _isEditing = true;
      _isManualEntry = false;
      _saveError = null;
      _clearUnsavedInputs();
    });
  }

  void _cancelReplacement() {
    if (_isSaving || !_hasCompleteSavedCredentials) return;
    _credentialUiGeneration++;
    setState(() {
      _isEditing = false;
      _isManualEntry = false;
      _saveError = null;
      _clearUnsavedInputs();
    });
  }

  void _toggleEntryMode() {
    if (!_inputsEnabled) return;
    _credentialUiGeneration++;
    setState(() {
      _isManualEntry = !_isManualEntry;
      _saveError = null;
      _clearUnsavedInputs();
    });
  }

  void _clearUnsavedInputs() {
    _bundleController.clear();
    _apiKeyController.clear();
    _secretKeyController.clear();
    _passphraseController.clear();
  }

  Future<void> _pasteFromClipboard() async {
    if (!_inputsEnabled || _isManualEntry) return;
    final requestGeneration = ++_credentialUiGeneration;
    final modeAtStart = _isManualEntry;
    setState(() {
      _isPastingFromClipboard = true;
      _saveError = null;
    });

    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted ||
          requestGeneration != _credentialUiGeneration ||
          modeAtStart != _isManualEntry ||
          _isSaving) {
        return;
      }
      final text = clipboard?.text;
      if (text == null || text.isEmpty) {
        setState(() {
          _saveError = 'Không thể đọc clipboard. Hãy sao chép lại rồi thử.';
        });
        return;
      }
      setState(() {
        _bundleController.text = text;
        _saveError = null;
      });
    } catch (_) {
      if (!mounted || requestGeneration != _credentialUiGeneration) return;
      setState(() {
        _saveError = 'Không thể đọc clipboard. Hãy sao chép lại rồi thử.';
      });
    } finally {
      if (mounted && requestGeneration == _credentialUiGeneration) {
        setState(() => _isPastingFromClipboard = false);
      }
    }
  }

  Future<void> _saveKeys() async {
    if (!_inputsEnabled || _isSaving) return;
    _credentialUiGeneration++;

    late final OkxCredentialBundle credentials;
    if (_isManualEntry) {
      if (!_formKey.currentState!.validate()) return;
      credentials = OkxCredentialBundle(
        apiKey: _apiKeyController.text.trim(),
        secretKey: _secretKeyController.text.trim(),
        passphrase: _passphraseController.text.trim(),
      );
    } else {
      try {
        credentials = OkxCredentialBundle.parse(_bundleController.text);
      } on FormatException {
        if (mounted) {
          setState(() {
            _saveError = OkxCredentialBundle.invalidInputMessage;
          });
        }
        return;
      } catch (_) {
        if (mounted) {
          setState(() {
            _saveError = OkxCredentialBundle.invalidInputMessage;
          });
        }
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(secureStorageProvider)
          .saveOkxCredentials(
            apiKey: credentials.apiKey,
            secretKey: credentials.secretKey,
            passphrase: credentials.passphrase,
          );
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _hasCompleteSavedCredentials = true;
        _isEditing = false;
        _isManualEntry = false;
        _clearUnsavedInputs();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveError = 'Không thể lưu thông tin API. Hãy thử lại.';
      });
    } finally {
      if (mounted && _isSaving) setState(() => _isSaving = false);
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
            if (_isLoading)
              _loadingCard()
            else if (_loadError != null)
              _loadErrorCard()
            else if (_hasCompleteSavedCredentials && !_isEditing)
              _savedSummaryCard()
            else
              _credentialEditorCard(mutedColor),
            const SizedBox(height: 24),
            const TradeSessionControls(),
          ],
        ),
      ),
    );
  }

  Widget _loadingCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Đang tải thông tin API đã lưu…'),
            SizedBox(height: 12),
            LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _loadErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_loadError!, key: const Key('settings-okx-load-error')),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('settings-retry-load-okx-credentials'),
              onPressed: _isSaving ? null : _retryLoad,
              child: const Text('Thử tải lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Đã lưu thông tin API trên thiết bị',
              key: Key('settings-okx-saved-summary'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thông tin được lưu cục bộ trên thiết bị hoặc trình duyệt này, '
              'không tự đồng bộ sang thiết bị khác.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('settings-change-okx-credentials'),
              onPressed: _isSaving ? null : _beginReplacement,
              child: const Text('Thay đổi key'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _credentialEditorCard(Color mutedColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Thông tin API được lưu cục bộ trên thiết bị hoặc trình duyệt '
                'này; ứng dụng không tự đồng bộ sang thiết bị khác.',
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
              const SizedBox(height: 20),
              if (_isManualEntry) ...[
                _credentialField(
                  controller: _apiKeyController,
                  key: const Key('settings-okx-api-key'),
                  label: 'API Key',
                  icon: Icons.key,
                ),
                const SizedBox(height: 16),
                _credentialField(
                  controller: _secretKeyController,
                  key: const Key('settings-okx-secret-key'),
                  label: 'Secret Key',
                  icon: Icons.security,
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                _credentialField(
                  controller: _passphraseController,
                  key: const Key('settings-okx-passphrase'),
                  label: 'Passphrase',
                  icon: Icons.lock,
                  obscureText: true,
                ),
              ] else ...[
                TextFormField(
                  key: const Key('settings-okx-credential-bundle'),
                  controller: _bundleController,
                  enabled: _inputsEnabled,
                  maxLines: 1,
                  minLines: 1,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: const InputDecoration(
                    labelText: 'Dán toàn bộ thông tin API',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key),
                    helperText:
                        'Sao chép nội dung rồi chọn “Dán từ clipboard”.\n'
                        'API Key: demo-api\n'
                        'Secret Key: demo-secret\n'
                        'Passphrase: demo-pass',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('settings-paste-okx-clipboard'),
                  onPressed: _inputsEnabled ? _pasteFromClipboard : null,
                  icon: _isPastingFromClipboard
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.content_paste),
                  label: Text(
                    _isPastingFromClipboard
                        ? 'Đang đọc clipboard…'
                        : 'Dán từ clipboard',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _saveError!,
                  key: const Key('settings-okx-input-error'),
                  style: TextStyle(color: AppPalette.of(context).negative),
                ),
              ],
              TextButton(
                key: const Key('settings-toggle-okx-entry-mode'),
                onPressed: _inputsEnabled ? _toggleEntryMode : null,
                child: Text(
                  _isManualEntry ? 'Dán toàn bộ một lần' : 'Nhập thủ công',
                ),
              ),
              if (_hasCompleteSavedCredentials) ...[
                OutlinedButton(
                  key: const Key('settings-cancel-okx-replacement'),
                  onPressed: _inputsEnabled ? _cancelReplacement : null,
                  child: const Text('Hủy thay đổi'),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('settings-save-okx-credentials'),
                onPressed: _inputsEnabled ? _saveKeys : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Lưu cấu hình'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _credentialField({
    required TextEditingController controller,
    required Key key,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      enabled: _inputsEnabled,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Không được để trống' : null,
    );
  }
}
