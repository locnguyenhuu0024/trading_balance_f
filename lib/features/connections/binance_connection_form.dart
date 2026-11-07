import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exchange/exchange_models.dart';
import '../../core/network/request_coordinator.dart';
import '../../core/security/secure_storage_helper.dart';
import '../../exchanges/binance/binance_adapter.dart';
import '../../exchanges/binance/binance_private_client.dart';

typedef BinanceConnectionTest =
    Future<void> Function(String key, String secret);

final binanceConnectionTestProvider = Provider<BinanceConnectionTest>((ref) {
  final isWeb = ref.watch(binanceIsWebProvider);
  return (key, secret) async {
    final state = ValueNotifier(
      const OkxCredentialSnapshot(generation: 0, rotating: false),
    );
    final client = BinancePrivateClient(
      keys: BinanceKeyBundle(apiKey: key, apiSecret: secret),
      credentialState: state,
      coordinator: RequestCoordinator(),
      isWeb: isWeb,
    );
    final failures = <ExchangeFailureKind>[];
    try {
      for (final path in [
        '/fapi/v3/account',
        if (!isWeb) '/api/v3/account',
        if (!isWeb) '/sapi/v1/margin/account',
        if (!isWeb) '/sapi/v1/margin/isolated/account',
      ]) {
        try {
          await client.get(path);
          return;
        } on BinancePrivateException catch (error) {
          failures.add(error.failure.kind);
        } catch (_) {
          failures.add(ExchangeFailureKind.other);
        }
      }
      throw BinancePrivateException(
        ExchangeFailure(
          failures.contains(ExchangeFailureKind.credential)
              ? ExchangeFailureKind.credential
              : failures.contains(ExchangeFailureKind.transient)
              ? ExchangeFailureKind.transient
              : ExchangeFailureKind.other,
        ),
      );
    } finally {
      state.dispose();
    }
  };
});

class BinanceConnectionForm extends ConsumerStatefulWidget {
  const BinanceConnectionForm({super.key});
  @override
  ConsumerState<BinanceConnectionForm> createState() =>
      _BinanceConnectionFormState();
}

class _BinanceConnectionFormState extends ConsumerState<BinanceConnectionForm> {
  final _key = TextEditingController();
  final _secret = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(secureStorageProvider);
    final key = await storage.getBinanceApiKey();
    final secret = await storage.getBinanceApiSecret();
    if (!mounted) return;
    if (_key.text.isEmpty) _key.text = key ?? '';
    if (_secret.text.isEmpty) _secret.text = secret ?? '';
  }

  @override
  void dispose() {
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(binanceConnectionTestProvider)(
        _key.text.trim(),
        _secret.text.trim(),
      );
      if (mounted) setState(() => _message = 'Kết nối thành công');
    } catch (error) {
      final kind = error is BinancePrivateException
          ? error.failure.kind
          : error is ArgumentError
          ? ExchangeFailureKind.credential
          : ExchangeFailureKind.other;
      if (mounted)
        setState(
          () => _message = switch (kind) {
            ExchangeFailureKind.credential => 'Khóa không hợp lệ',
            ExchangeFailureKind.transient => 'Không có kết nối mạng',
            _ => 'Không thể kiểm tra kết nối',
          },
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_key.text.trim().isEmpty || _secret.text.trim().isEmpty) {
      setState(() => _message = 'Vui lòng nhập khóa và khóa bí mật');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(secureStorageProvider)
          .saveBinanceKeys(
            apiKey: _key.text.trim(),
            apiSecret: _secret.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _message = 'Không thể lưu kết nối');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa kết nối'),
        content: const Text('Bạn có chắc muốn xóa kết nối Binance?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa kết nối'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(secureStorageProvider).clearBinanceKeys();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _message = 'Không thể xóa kết nối');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Binance')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Tên tài khoản'),
        const Text('Chính'),
        const SizedBox(height: 16),
        TextField(
          controller: _key,
          decoration: const InputDecoration(labelText: 'API key'),
        ),
        TextField(
          controller: _secret,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Khóa bí mật'),
        ),
        const SizedBox(height: 12),
        const Text('Dùng khóa chỉ đọc'),
        if (_message != null) Text(_message!),
        TextButton(
          onPressed: _busy ? null : _test,
          child: const Text('Kiểm tra kết nối'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Lưu')),
        TextButton(
          onPressed: _busy ? null : _delete,
          child: const Text('Xóa kết nối'),
        ),
      ],
    ),
  );
}
