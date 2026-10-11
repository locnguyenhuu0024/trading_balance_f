import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/main_navigation_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive_form_content.dart';
import '../data/multi_user_api_client.dart';
import 'providers/multi_user_provider.dart';

class MultiUserEntryScreen extends ConsumerStatefulWidget {
  const MultiUserEntryScreen({super.key});

  @override
  ConsumerState<MultiUserEntryScreen> createState() =>
      _MultiUserEntryScreenState();
}

class _MultiUserEntryScreenState extends ConsumerState<MultiUserEntryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(multiUserControllerProvider).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(multiUserControllerProvider);
    final session = ref.watch(userSessionStoreProvider).current;
    if (controller.isRestoring) {
      return const _EntryProgress(label: 'Đang kiểm tra phiên máy chủ…');
    }
    final enrollment = controller.activeEnrollment;
    if (enrollment != null) {
      return _EnrollmentScreen(bootstrap: enrollment);
    }
    if (session?.canReadPrivate == true) return const MainNavigationShell();
    return const _ServerLoginScreen();
  }
}

class _ServerLoginScreen extends ConsumerStatefulWidget {
  const _ServerLoginScreen();

  @override
  ConsumerState<_ServerLoginScreen> createState() => _ServerLoginScreenState();
}

class _ServerLoginScreenState extends ConsumerState<_ServerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _proof = TextEditingController();
  final _invite = TextEditingController();
  final _inviteFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _proofFocus = FocusNode();
  bool _activation = false;
  bool _recovery = false;

  @override
  void dispose() {
    _password.clear();
    _proof.clear();
    _invite.clear();
    _username.dispose();
    _password.dispose();
    _proof.dispose();
    _invite.dispose();
    _inviteFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _proofFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(multiUserControllerProvider);
    if (controller.isBusy || !_validateAndFocus()) return;
    final activating = _activation;
    final username = _username.text.trim();
    final password = _password.text;
    final proof = _proof.text.trim();
    final invite = _invite.text.trim();
    try {
      if (activating) {
        await controller.activateInvite(
          inviteToken: invite,
          username: username,
          password: password,
        );
      } else {
        await controller.login(
          username: username,
          password: password,
          proof: proof,
          recoveryCode: _recovery,
        );
      }
    } catch (_) {
      // The controller exposes a sanitized message for this screen.
    } finally {
      if (mounted) {
        _password.clear();
        _proof.clear();
        _invite.clear();
      }
    }
  }

  bool _validateAndFocus() {
    if (_formKey.currentState?.validate() != true) {
      if (_activation && _invite.text.trim().isEmpty) {
        _inviteFocus.requestFocus();
      } else if (_username.text.trim().isEmpty) {
        _usernameFocus.requestFocus();
      } else if (_password.text.isEmpty) {
        _passwordFocus.requestFocus();
      } else if (!_activation && _proofError(_proof.text) != null) {
        _proofFocus.requestFocus();
      }
      return false;
    }
    return true;
  }

  String? _proofError(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _recovery ? 'Nhập mã khôi phục.' : 'Nhập mã TOTP.';
    }
    if (!_recovery && !RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return 'Nhập mã TOTP gồm 6 chữ số.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final controller = ref.watch(multiUserControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản giao dịch')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.space4),
            child: ResponsiveFormContent(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.security_rounded,
                          size: 48,
                          color: palette.ink,
                        ),
                        const SizedBox(height: AppTokens.space3),
                        Text(
                          _activation
                              ? 'Kích hoạt tài khoản'
                              : 'Đăng nhập an toàn',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppTokens.space2),
                        Text(
                          'Dữ liệu riêng tư được tải qua phiên máy chủ có MFA. Khóa sàn chỉ được gửi để máy chủ xác minh và lưu kết nối.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.muted),
                        ),
                        const SizedBox(height: AppTokens.space5),
                        if (_activation) ...[
                          _EntryField(
                            controller: _invite,
                            label: 'Mã mời',
                            keyName: 'invite-token',
                            obscure: true,
                            focusNode: _inviteFocus,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Nhập mã mời.'
                                : null,
                            onSubmitted: (_) => _usernameFocus.requestFocus(),
                          ),
                          const SizedBox(height: AppTokens.space3),
                        ],
                        _EntryField(
                          controller: _username,
                          label: 'Tên đăng nhập',
                          keyName: 'username',
                          focusNode: _usernameFocus,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Nhập tên đăng nhập.'
                              : null,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: AppTokens.space3),
                        _EntryField(
                          controller: _password,
                          label: 'Mật khẩu',
                          keyName: 'password',
                          obscure: true,
                          focusNode: _passwordFocus,
                          validator: (value) => value == null || value.isEmpty
                              ? 'Nhập mật khẩu.'
                              : null,
                          textInputAction: _activation
                              ? TextInputAction.done
                              : TextInputAction.next,
                          onSubmitted: (_) => _activation
                              ? _submit()
                              : _proofFocus.requestFocus(),
                        ),
                        if (!_activation) ...[
                          const SizedBox(height: AppTokens.space3),
                          _EntryField(
                            controller: _proof,
                            label: _recovery ? 'Mã khôi phục' : 'Mã TOTP',
                            keyName: 'mfa-proof',
                            focusNode: _proofFocus,
                            obscure: _recovery,
                            keyboardType: _recovery
                                ? TextInputType.text
                                : TextInputType.number,
                            textInputAction: TextInputAction.done,
                            validator: _proofError,
                            onSubmitted: (_) => _submit(),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: controller.isBusy
                                  ? null
                                  : () =>
                                        setState(() => _recovery = !_recovery),
                              child: Text(
                                _recovery
                                    ? 'Dùng mã TOTP'
                                    : 'Dùng mã khôi phục',
                              ),
                            ),
                          ),
                        ],
                        if (controller.errorMessage != null)
                          _StatusBanner(
                            text: controller.errorMessage!,
                            error: true,
                          ),
                        if (controller.statusMessage != null)
                          _StatusBanner(text: controller.statusMessage!),
                        const SizedBox(height: AppTokens.space2),
                        FilledButton(
                          key: const Key('server-auth-submit'),
                          onPressed: controller.isBusy ? null : _submit,
                          child: controller.isBusy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_activation ? 'Kích hoạt' : 'Đăng nhập'),
                        ),
                        TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : () => setState(() {
                                  _activation = !_activation;
                                  _recovery = false;
                                  _proof.clear();
                                }),
                          child: Text(
                            _activation
                                ? 'Đã kích hoạt? Đăng nhập'
                                : 'Có mã mời? Kích hoạt tài khoản',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnrollmentScreen extends ConsumerStatefulWidget {
  const _EnrollmentScreen({required this.bootstrap});

  final AuthBootstrap bootstrap;

  @override
  ConsumerState<_EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<_EnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _totp = TextEditingController();
  final _totpFocus = FocusNode();
  final _recoveryCodesFocus = FocusNode();
  bool _codesSaved = false;
  String? _formError;

  @override
  void dispose() {
    _totp.clear();
    _totp.dispose();
    _totpFocus.dispose();
    _recoveryCodesFocus.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final controller = ref.read(multiUserControllerProvider);
    if (controller.isBusy || _formKey.currentState?.validate() != true) {
      _totpFocus.requestFocus();
      return;
    }
    if (!_codesSaved) {
      setState(() => _formError = 'Hãy xác nhận đã lưu mã khôi phục.');
      _recoveryCodesFocus.requestFocus();
      return;
    }
    final totp = _totp.text.trim();
    try {
      await ref.read(multiUserControllerProvider).completeEnrollment(totp);
    } catch (_) {
      // The controller exposes a sanitized message for this screen.
    } finally {
      if (mounted) _totp.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final controller = ref.watch(multiUserControllerProvider);
    final secret = widget.bootstrap.totpSecret ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết lập MFA'),
        actions: [
          IconButton(
            tooltip: 'Hủy và đăng xuất',
            onPressed: controller.isBusy ? null : controller.logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.space4),
          child: ResponsiveFormContent(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Lưu mã khôi phục ở nơi an toàn',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppTokens.space2),
                  Text(
                    'Mã bí mật và mã khôi phục chỉ hiển thị trong phiên này. Ứng dụng không lưu chúng.',
                    style: TextStyle(color: palette.muted),
                  ),
                  const SizedBox(height: AppTokens.space4),
                  SelectableText('Mã thiết lập TOTP\n$secret'),
                  const SizedBox(height: AppTokens.space3),
                  ...widget.bootstrap.recoveryCodes.map(
                    (code) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: SelectableText(code),
                      trailing: IconButton(
                        tooltip: 'Sao chép mã khôi phục',
                        constraints: const BoxConstraints(
                          minWidth: AppTokens.minimumTouchTarget,
                          minHeight: AppTokens.minimumTouchTarget,
                        ),
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: code)),
                      ),
                    ),
                  ),
                  Focus(
                    focusNode: _recoveryCodesFocus,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _codesSaved,
                      onChanged: controller.isBusy
                          ? null
                          : (value) => setState(() {
                              _codesSaved = value == true;
                              _formError = null;
                            }),
                      key: const Key('recovery-codes-saved-focus'),
                      title: const Text(
                        'Tôi đã lưu mã khôi phục ở nơi an toàn',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      minTileHeight: AppTokens.minimumTouchTarget,
                    ),
                  ),
                  _EntryField(
                    controller: _totp,
                    label: 'Mã TOTP',
                    keyName: 'enrollment-totp',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    focusNode: _totpFocus,
                    validator: (value) =>
                        value == null ||
                            !RegExp(r'^\d{6}$').hasMatch(value.trim())
                        ? 'Nhập mã TOTP gồm 6 chữ số.'
                        : null,
                    onSubmitted: (_) => _complete(),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_formError != null)
                    _StatusBanner(text: _formError!, error: true),
                  if (controller.errorMessage != null)
                    _StatusBanner(text: controller.errorMessage!, error: true),
                  if (controller.statusMessage != null)
                    _StatusBanner(text: controller.statusMessage!),
                  const SizedBox(height: AppTokens.space3),
                  FilledButton(
                    key: const Key('mfa-enrollment-complete'),
                    onPressed:
                        controller.isBusy || !_codesSaved || _totp.text.isEmpty
                        ? null
                        : _complete,
                    child: controller.isBusy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Hoàn tất và đăng nhập lại'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryField extends StatelessWidget {
  const _EntryField({
    required this.controller,
    required this.label,
    required this.keyName,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.focusNode,
    this.validator,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String keyName;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: Key(keyName),
    controller: controller,
    onChanged: onChanged,
    obscureText: obscure,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    focusNode: focusNode,
    validator: validator,
    onFieldSubmitted: onSubmitted,
    autocorrect: false,
    enableSuggestions: false,
    minLines: 1,
    maxLines: 1,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.space2),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: TextStyle(color: error ? palette.negative : palette.muted),
        ),
      ),
    );
  }
}

class _EntryProgress extends StatelessWidget {
  const _EntryProgress({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppTokens.space3),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
