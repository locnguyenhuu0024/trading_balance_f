import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/session/user_session.dart';
import '../../../core/widgets/responsive_form_content.dart';
import '../domain/connection_models.dart';
import 'providers/multi_user_provider.dart';

Future<({String password, String totp})?> showConnectionStepUpDialog(
  BuildContext context, {
  required UserSession owner,
}) => showDialog<({String password, String totp})>(
  context: context,
  builder: (_) => _StepUpDialog(owner: owner),
);

class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key});

  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  late Future<List<ConnectionRecord>> _connections;
  late final UserSessionStore _sessions;
  UserSession? _ownerAtMount;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(userSessionStoreProvider);
    _ownerAtMount = _sessions.current;
    _revoked = _ownerAtMount == null;
    _sessions.addListener(_handleAuthorityChanged);
    _connections = Future<List<ConnectionRecord>>.value(const []);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  bool get _ownerStillCurrent {
    final owner = _ownerAtMount;
    final current = _sessions.current;
    return owner != null &&
        current != null &&
        current.sameIdentity(owner) &&
        current.bearerToken == owner.bearerToken;
  }

  void _handleAuthorityChanged() {
    if (_ownerStillCurrent || !mounted || _revoked) return;
    setState(() {
      _revoked = true;
      _connections = Future<List<ConnectionRecord>>.value(const []);
    });
  }

  @override
  void dispose() {
    _sessions.removeListener(_handleAuthorityChanged);
    super.dispose();
  }

  void _refresh() {
    if (!mounted || !_ownerStillCurrent) {
      _handleAuthorityChanged();
      return;
    }
    final owner = _ownerAtMount!;
    setState(() {
      _connections = _loadConnections(owner);
    });
  }

  Future<List<ConnectionRecord>> _loadConnections(UserSession owner) async {
    final generation = _sessions.generation;
    final connections = await ref
        .read(multiUserControllerProvider)
        .getConnections();
    if (!mounted ||
        !_ownerStillCurrent ||
        !_sessions.matches(generation, owner)) {
      return const [];
    }
    return connections;
  }

  Future<void> _addConnection() async {
    if (!_ownerStillCurrent) {
      _handleAuthorityChanged();
      return;
    }
    final owner = _ownerAtMount!;
    final created = await showDialog<ConnectionRecord>(
      context: context,
      builder: (_) => _AddConnectionDialog(owner: owner),
    );
    if (created == null || !mounted || !_ownerStillCurrent) {
      _refresh();
      return;
    }
    final product = _products(created.exchange).first;
    ref.read(multiUserControllerProvider).selectConnection(created, product);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final session = ref.watch(userSessionStoreProvider).current;
    final controller = ref.watch(multiUserControllerProvider);
    final scopes = ref.watch(connectionScopeStoreProvider);
    final hasOwner = !_revoked && _ownerStillCurrent;
    return Scaffold(
      appBar: AppBar(
        title: const Text('API và kết nối'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: controller.isBusy ? null : controller.logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.space4),
            children: [
              Text(
                'Phiên máy chủ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTokens.space2),
              Text(
                !hasOwner || session == null
                    ? 'Chưa đăng nhập.'
                    : '${session.username} · xác thực ${session.mode}',
                style: TextStyle(color: palette.muted),
              ),
              if (hasOwner && session?.canTrade == true)
                const _InfoCard(
                  icon: Icons.verified_user_outlined,
                  text:
                      'Xác minh TOTP gần đây đang bật cho các thao tác nhạy cảm.',
                )
              else
                const _InfoCard(
                  icon: Icons.lock_clock_outlined,
                  text:
                      'Kết nối mới và thao tác yêu cầu xác minh mật khẩu cùng TOTP.',
                ),
              const SizedBox(height: AppTokens.space5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kết nối đã xác minh',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tải lại kết nối',
                    onPressed: _refresh,
                    constraints: const BoxConstraints(
                      minWidth: AppTokens.minimumTouchTarget,
                      minHeight: AppTokens.minimumTouchTarget,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.space2),
              if (!hasOwner)
                const _InlineState(
                  icon: Icons.lock_outline_rounded,
                  text:
                      'Phiên đã thay đổi. Hãy mở lại trang sau khi đăng nhập.',
                )
              else
                FutureBuilder<List<ConnectionRecord>>(
                  future: _connections,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(AppTokens.space5),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return _InlineState(
                        icon: Icons.cloud_off_outlined,
                        text:
                            'Không thể tải kết nối. ${_errorText(snapshot.error)}',
                        action: TextButton(
                          onPressed: _refresh,
                          child: const Text('Thử lại'),
                        ),
                      );
                    }
                    final connections = snapshot.data ?? const [];
                    if (connections.isEmpty) {
                      return const _InlineState(
                        icon: Icons.link_off_rounded,
                        text: 'Chưa có kết nối sàn nào được xác minh.',
                      );
                    }
                    return Column(
                      children: [
                        for (final connection in connections)
                          _ConnectionCard(
                            connection: connection,
                            selected:
                                scopes.current?.connectionId ==
                                connection.connectionId,
                            selectedProduct:
                                scopes.current?.connectionId ==
                                    connection.connectionId
                                ? scopes.current?.product
                                : null,
                            onSelect: (product) {
                              ref
                                  .read(multiUserControllerProvider)
                                  .selectConnection(connection, product);
                            },
                          ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: AppTokens.space3),
              OutlinedButton.icon(
                key: const Key('add-verified-connection'),
                onPressed:
                    !hasOwner ||
                        controller.isBusy ||
                        session?.canReadPrivate != true
                    ? null
                    : _addConnection,
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Thêm kết nối sàn'),
              ),
              if (controller.statusMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.space3),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      controller.statusMessage!,
                      style: TextStyle(color: palette.muted),
                    ),
                  ),
                ),
              if (controller.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.space2),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      controller.errorMessage!,
                      style: TextStyle(color: palette.negative),
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

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.selected,
    required this.selectedProduct,
    required this.onSelect,
  });

  final ConnectionRecord connection;
  final bool selected;
  final String? selectedProduct;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final products = _products(connection.exchange);
    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.space2),
      color: selected ? palette.surface : palette.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: selected ? palette.ink : palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.link_rounded, color: palette.ink),
                const SizedBox(width: AppTokens.space2),
                Expanded(
                  child: Text(
                    connection.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(connection.status),
              ],
            ),
            const SizedBox(height: AppTokens.space1),
            Text(
              '${connection.exchange} · ${connection.environment} · ${connection.region}',
              style: TextStyle(color: palette.muted),
            ),
            if (connection.status == 'RECONCILING')
              Text(
                'Máy chủ đang đồng bộ quyền. Dữ liệu có thể chưa đầy đủ.',
                style: TextStyle(color: palette.warning),
              ),
            const SizedBox(height: AppTokens.space2),
            DropdownButtonFormField<String>(
              value: products.contains(selectedProduct)
                  ? selectedProduct
                  : null,
              decoration: const InputDecoration(
                labelText: 'Sản phẩm',
                border: OutlineInputBorder(),
              ),
              items: products
                  .map(
                    (product) =>
                        DropdownMenuItem(value: product, child: Text(product)),
                  )
                  .toList(growable: false),
              onChanged: connection.isAvailable
                  ? (product) {
                      if (product != null) onSelect(product);
                    }
                  : null,
            ),
            const SizedBox(height: AppTokens.space1),
            Text(
              selected
                  ? 'Đang xem dữ liệu của kết nối này.'
                  : 'Chọn sản phẩm để xem dữ liệu riêng tư.',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Card(
      color: palette.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: palette.ink),
            const SizedBox(width: AppTokens.space2),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: AppTokens.space2),
          Text(text, textAlign: TextAlign.center),
          if (action != null) action!,
        ],
      ),
    ),
  );
}

class _AddConnectionDialog extends ConsumerStatefulWidget {
  const _AddConnectionDialog({required this.owner});

  final UserSession owner;

  @override
  ConsumerState<_AddConnectionDialog> createState() =>
      _AddConnectionDialogState();
}

class _AddConnectionDialogState extends ConsumerState<_AddConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _apiKey = TextEditingController();
  final _apiSecret = TextEditingController();
  final _passphrase = TextEditingController();
  final _apiKeyFocus = FocusNode();
  final _apiSecretFocus = FocusNode();
  final _passphraseFocus = FocusNode();
  String _exchange = 'OKX';
  String _environment = 'demo';
  String _region = 'global';
  bool _offerLegacyRemoval = false;
  bool _secretVisible = false;
  bool _busy = false;
  String? _error;
  late final UserSessionStore _sessions;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(userSessionStoreProvider);
    _sessions.addListener(_handleAuthorityChanged);
  }

  bool get _ownerStillCurrent {
    final current = _sessions.current;
    return current != null &&
        current.sameIdentity(widget.owner) &&
        current.bearerToken == widget.owner.bearerToken;
  }

  void _handleAuthorityChanged() {
    if (_ownerStillCurrent || !mounted || _revoked) return;
    _revoked = true;
    _clearAllInputs();
    setState(() => _error = 'Phiên đã thay đổi. Hãy đăng nhập lại.');
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route != null) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _sessions.removeListener(_handleAuthorityChanged);
    _nickname.dispose();
    _apiKey.clear();
    _apiKey.dispose();
    _apiSecret.clear();
    _apiSecret.dispose();
    _passphrase.clear();
    _passphrase.dispose();
    _apiKeyFocus.dispose();
    _apiSecretFocus.dispose();
    _passphraseFocus.dispose();
    super.dispose();
  }

  Future<void> _paste(TextEditingController controller) async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboard?.text != null && mounted) {
        controller.text = clipboard!.text!.trim();
        setState(() {});
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Không thể đọc nội dung đã sao chép.');
    }
  }

  Future<bool> _ensureStepUp() async {
    if (!_ownerStillCurrent || _revoked) return false;
    final controller = ref.read(multiUserControllerProvider);
    if (controller.currentSession?.canTrade == true) return true;
    final before = controller.currentSession;
    if (before == null ||
        !before.sameIdentity(widget.owner) ||
        before.bearerToken != widget.owner.bearerToken) {
      return false;
    }
    final credentials = await showDialog<({String password, String totp})>(
      context: context,
      builder: (_) => _StepUpDialog(owner: widget.owner),
    );
    if (!mounted || credentials == null || !_ownerStillCurrent) return false;
    try {
      if (!_ownerStillCurrent) return false;
      await controller.stepUp(
        password: credentials.password,
        totp: credentials.totp,
      );
      final after = controller.currentSession;
      return mounted &&
          _ownerStillCurrent &&
          after?.sameIdentity(before) == true &&
          after?.bearerToken == widget.owner.bearerToken &&
          after?.canTrade == true;
    } catch (_) {
      if (mounted && _ownerStillCurrent) {
        setState(() => _error = controller.errorMessage);
      }
      return false;
    }
  }

  Future<void> _submit() async {
    if (_busy || !_validateAndFocus()) return;
    final exchange = _exchange;
    final environment = _environment;
    final region = _region;
    final nickname = _nickname.text.trim();
    final apiKey = _apiKey.text;
    final apiSecret = _apiSecret.text;
    final passphrase = exchange == 'OKX' ? _passphrase.text : null;
    final offerLegacyRemoval = _offerLegacyRemoval;
    if (!_ownerStillCurrent || _revoked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _ensureStepUp() || !mounted) return;
      if (!_ownerStillCurrent) return;
      final controller = ref.read(multiUserControllerProvider);
      final owner = controller.currentSession;
      final sessions = ref.read(userSessionStoreProvider);
      final ownerGeneration = sessions.generation;
      if (owner == null ||
          !owner.canTrade ||
          !owner.sameIdentity(widget.owner) ||
          owner.bearerToken != widget.owner.bearerToken) {
        return;
      }
      final record = await controller.createConnection(
        exchange: exchange,
        environment: environment,
        region: region,
        nickname: nickname,
        apiKey: apiKey,
        apiSecret: apiSecret,
        passphrase: passphrase,
      );
      if (!mounted ||
          !_ownerStillCurrent ||
          !sessions.matches(ownerGeneration, owner))
        return;
      _clearEphemeralSecrets();
      if (offerLegacyRemoval) {
        final remove = await showDialog<bool>(
          context: context,
          builder: (_) => _LegacyRemovalDialog(owner: widget.owner),
        );
        if (remove == true && mounted && _ownerStillCurrent) {
          try {
            await ref
                .read(multiUserControllerProvider)
                .storage
                .clearOkxCredentials();
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Kết nối đã được xác minh; không thể xóa khóa OKX cũ trên thiết bị.',
                  ),
                ),
              );
              Navigator.of(context).pop(record);
            }
            return;
          }
        }
      }
      if (mounted && _ownerStillCurrent) Navigator.of(context).pop(record);
    } catch (_) {
      if (mounted && _ownerStillCurrent) {
        setState(() {
          _error =
              ref.read(multiUserControllerProvider).errorMessage ??
              'Không thể xác minh kết nối. Khóa chưa được lưu trên thiết bị.';
        });
      }
    } finally {
      if (mounted) {
        _clearEphemeralSecrets();
        setState(() => _busy = false);
      }
    }
  }

  bool _validateAndFocus() {
    if (_formKey.currentState?.validate() != true) {
      if (_apiKey.text.trim().isEmpty) {
        _apiKeyFocus.requestFocus();
      } else if (_apiSecret.text.isEmpty) {
        _apiSecretFocus.requestFocus();
      } else if (_exchange == 'OKX' && _passphrase.text.trim().isEmpty) {
        _passphraseFocus.requestFocus();
      }
      return false;
    }
    return true;
  }

  void _clearEphemeralSecrets() {
    if (!mounted) return;
    _apiKey.clear();
    _apiSecret.clear();
    _passphrase.clear();
  }

  void _clearAllInputs() {
    if (!mounted) return;
    _nickname.clear();
    _clearEphemeralSecrets();
    _secretVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      title: const Text('Thêm kết nối sàn'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: ResponsiveFormContent(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nhập lại thông tin thủ công. Ứng dụng không đọc hoặc điền sẵn khóa cũ.',
                    style: TextStyle(color: palette.muted),
                  ),
                  const SizedBox(height: AppTokens.space3),
                  DropdownButtonFormField<String>(
                    value: _exchange,
                    decoration: const InputDecoration(
                      labelText: 'Sàn',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'OKX', child: Text('OKX')),
                      DropdownMenuItem(
                        value: 'BINANCE',
                        child: Text('Binance'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _exchange = value ?? 'OKX'),
                  ),
                  const SizedBox(height: AppTokens.space2),
                  DropdownButtonFormField<String>(
                    value: _environment,
                    decoration: const InputDecoration(
                      labelText: 'Môi trường',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'demo', child: Text('Demo')),
                      DropdownMenuItem(
                        value: 'production',
                        child: Text('Production'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) =>
                              setState(() => _environment = value ?? 'demo'),
                  ),
                  const SizedBox(height: AppTokens.space2),
                  DropdownButtonFormField<String>(
                    value: _region,
                    decoration: const InputDecoration(
                      labelText: 'Khu vực API',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'global', child: Text('Global')),
                      DropdownMenuItem(value: 'us', child: Text('US')),
                      DropdownMenuItem(value: 'eu', child: Text('EU')),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) =>
                              setState(() => _region = value ?? 'global'),
                  ),
                  const SizedBox(height: AppTokens.space2),
                  TextField(
                    controller: _nickname,
                    decoration: const InputDecoration(
                      labelText: 'Tên hiển thị (không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppTokens.space2),
                  _CredentialField(
                    controller: _apiKey,
                    label: 'API key',
                    keyName: 'connection-api-key',
                    obscure: !_secretVisible,
                    focusNode: _apiKeyFocus,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Nhập API key.'
                        : null,
                    onSubmitted: (_) => _apiSecretFocus.requestFocus(),
                    onPaste: () => _paste(_apiKey),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppTokens.space2),
                  _CredentialField(
                    controller: _apiSecret,
                    label: 'API secret',
                    keyName: 'connection-api-secret',
                    obscure: !_secretVisible,
                    focusNode: _apiSecretFocus,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Nhập API secret.'
                        : null,
                    onSubmitted: (_) => _exchange == 'OKX'
                        ? _passphraseFocus.requestFocus()
                        : _submit(),
                    onPaste: () => _paste(_apiSecret),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_exchange == 'OKX') ...[
                    const SizedBox(height: AppTokens.space2),
                    _CredentialField(
                      controller: _passphrase,
                      label: 'Passphrase',
                      keyName: 'connection-passphrase',
                      obscure: !_secretVisible,
                      focusNode: _passphraseFocus,
                      validator: (value) =>
                          _exchange == 'OKX' &&
                              (value == null || value.trim().isEmpty)
                          ? 'Nhập passphrase.'
                          : null,
                      onSubmitted: (_) => _submit(),
                      onPaste: () => _paste(_passphrase),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _secretVisible,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _secretVisible = value),
                    title: const Text('Hiện khóa trong lúc nhập'),
                    minTileHeight: AppTokens.minimumTouchTarget,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _offerLegacyRemoval,
                    onChanged: _busy
                        ? null
                        : (value) => setState(
                            () => _offerLegacyRemoval = value == true,
                          ),
                    title: const Text(
                      'Sau khi xác minh, hỏi tôi về việc xóa khóa OKX cũ trên thiết bị',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    minTileHeight: AppTokens.minimumTouchTarget,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTokens.space2),
                      child: Text(
                        _error!,
                        style: TextStyle(color: palette.negative),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy || _revoked
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('verify-connection-submit'),
          onPressed:
              _busy ||
                  _revoked ||
                  !_ownerStillCurrent ||
                  _apiKey.text.isEmpty ||
                  _apiSecret.text.isEmpty
              ? null
              : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Xác minh và lưu kết nối'),
        ),
      ],
    );
  }
}

class _CredentialField extends StatelessWidget {
  const _CredentialField({
    required this.controller,
    required this.label,
    required this.keyName,
    required this.obscure,
    required this.onPaste,
    this.focusNode,
    this.validator,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String keyName;
  final bool obscure;
  final VoidCallback onPaste;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: Key(keyName),
    controller: controller,
    onChanged: onChanged,
    onFieldSubmitted: onSubmitted,
    focusNode: focusNode,
    validator: validator,
    obscureText: obscure,
    textInputAction: TextInputAction.next,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: 'Dán $label',
        constraints: const BoxConstraints(
          minWidth: AppTokens.minimumTouchTarget,
          minHeight: AppTokens.minimumTouchTarget,
        ),
        onPressed: onPaste,
        icon: const Icon(Icons.content_paste_rounded),
      ),
    ),
  );
}

class _StepUpDialog extends ConsumerStatefulWidget {
  const _StepUpDialog({required this.owner});

  final UserSession owner;

  @override
  ConsumerState<_StepUpDialog> createState() => _StepUpDialogState();
}

class _StepUpDialogState extends ConsumerState<_StepUpDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _totp = TextEditingController();
  final _passwordFocus = FocusNode();
  final _totpFocus = FocusNode();
  late final UserSessionStore _sessions;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(userSessionStoreProvider);
    _sessions.addListener(_handleAuthorityChanged);
  }

  bool get _ownerStillCurrent {
    final current = _sessions.current;
    return current != null &&
        current.sameIdentity(widget.owner) &&
        current.bearerToken == widget.owner.bearerToken;
  }

  void _handleAuthorityChanged() {
    if (_ownerStillCurrent || !mounted || _revoked) return;
    _revoked = true;
    _password.clear();
    _totp.clear();
    setState(() {});
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route != null) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _sessions.removeListener(_handleAuthorityChanged);
    _password.clear();
    _password.dispose();
    _totp.clear();
    _totp.dispose();
    _passwordFocus.dispose();
    _totpFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_revoked ||
        !_ownerStillCurrent ||
        _formKey.currentState?.validate() != true) {
      if (_password.text.isEmpty) {
        _passwordFocus.requestFocus();
      } else {
        _totpFocus.requestFocus();
      }
      return;
    }
    Navigator.pop(context, (password: _password.text, totp: _totp.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xác minh lại'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _password,
            focusNode: _passwordFocus,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) => _totpFocus.requestFocus(),
            textInputAction: TextInputAction.next,
            validator: (value) =>
                value == null || value.isEmpty ? 'Nhập mật khẩu.' : null,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Mật khẩu',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          TextFormField(
            controller: _totp,
            focusNode: _totpFocus,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) => _submit(),
            textInputAction: TextInputAction.done,
            validator: (value) =>
                value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())
                ? 'Nhập mã TOTP gồm 6 chữ số.'
                : null,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Mã TOTP',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed:
            _revoked ||
                !_ownerStillCurrent ||
                _password.text.isEmpty ||
                !RegExp(r'^\d{6}$').hasMatch(_totp.text.trim())
            ? null
            : _submit,
        child: const Text('Xác minh'),
      ),
    ],
  );
}

class _LegacyRemovalDialog extends ConsumerStatefulWidget {
  const _LegacyRemovalDialog({required this.owner});

  final UserSession owner;

  @override
  ConsumerState<_LegacyRemovalDialog> createState() =>
      _LegacyRemovalDialogState();
}

class _LegacyRemovalDialogState extends ConsumerState<_LegacyRemovalDialog> {
  late final UserSessionStore _sessions;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(userSessionStoreProvider);
    _sessions.addListener(_handleAuthorityChanged);
  }

  bool get _ownerStillCurrent {
    final current = _sessions.current;
    return current != null &&
        current.sameIdentity(widget.owner) &&
        current.bearerToken == widget.owner.bearerToken;
  }

  void _handleAuthorityChanged() {
    if (_ownerStillCurrent || !mounted || _revoked) return;
    _revoked = true;
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route != null) {
        Navigator.of(context).removeRoute(route, false);
      }
    });
  }

  @override
  void dispose() {
    _sessions.removeListener(_handleAuthorityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xóa khóa đã lưu từ phiên bản cũ?'),
    content: const Text(
      'Kết nối mới đã được máy chủ xác minh và gắn với tài khoản này. Bạn có thể xóa các khóa OKX cũ đang lưu trên thiết bị. Việc này không thể hoàn tác.',
    ),
    actions: [
      TextButton(
        onPressed: _revoked ? null : () => Navigator.pop(context, false),
        child: const Text('Giữ lại'),
      ),
      FilledButton(
        onPressed: _revoked || !_ownerStillCurrent
            ? null
            : () => Navigator.pop(context, true),
        child: const Text('Xóa khóa cũ'),
      ),
    ],
  );
}

List<String> _products(String exchange) => exchange == 'OKX'
    ? const ['SPOT', 'MARGIN', 'SWAP', 'FUTURES']
    : const ['SPOT', 'USD_M'];

String _errorText(Object? error) {
  if (error is Error) return 'Dữ liệu chưa sẵn sàng.';
  return error?.toString() ?? 'Hãy thử lại.';
}
