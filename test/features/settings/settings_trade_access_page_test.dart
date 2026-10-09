import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_trade_access_page.dart';

class _FakeStorage extends SecureStorageHelper {
  _FakeStorage({
    this.apiKey,
    this.secretKey,
    this.passphrase,
    this.loadGate,
    this.saveGate,
  }) : super(const FlutterSecureStorage());

  String? apiKey;
  String? secretKey;
  String? passphrase;
  Completer<void>? loadGate;
  Completer<void>? saveGate;
  bool failLoad = false;
  bool failSave = false;
  int saveCalls = 0;
  final List<Map<String, String>> saves = [];

  Future<String?> _read(String? value) async {
    await loadGate?.future;
    if (failLoad) throw StateError('synthetic load failure with private data');
    return value;
  }

  @override
  Future<String?> getOkxApiKey() => _read(apiKey);

  @override
  Future<String?> getOkxSecretKey() => _read(secretKey);

  @override
  Future<String?> getOkxPassphrase() => _read(passphrase);

  @override
  Future<void> saveOkxCredentials({
    required String apiKey,
    required String secretKey,
    required String passphrase,
  }) async {
    saveCalls++;
    await saveGate?.future;
    if (failSave) throw StateError('synthetic save failure with private data');
    saves.add({
      'apiKey': apiKey,
      'secretKey': secretKey,
      'passphrase': passphrase,
    });
    this.apiKey = apiKey;
    this.secretKey = secretKey;
    this.passphrase = passphrase;
  }
}

class _FakeTradeApi implements TradeApi {
  @override
  bool get isConfigured => false;

  @override
  bool get supportsSessionRestoration => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _settingsPage(_FakeStorage storage) {
  final api = _FakeTradeApi();
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      tradeApiProvider.overrideWithValue(api),
      tradeSessionProvider.overrideWith((ref) => TradeSessionController(api)),
    ],
    child: const MaterialApp(home: SettingsTradeAccessPage()),
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _settlePage(WidgetTester tester, _FakeStorage storage) async {
  await tester.pumpWidget(_settingsPage(storage));
  await tester.pumpAndSettle();
}

void _mockClipboard(
  Future<Object?> Function() response, {
  void Function()? onRead,
}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method != 'Clipboard.getData') return null;
    onRead?.call();
    return response();
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

void main() {
  testWidgets('shows a saved summary and cancel preserves stored credentials', (
    tester,
  ) async {
    final storage = _FakeStorage(
      apiKey: 'saved-api-value',
      secretKey: 'saved-secret-value',
      passphrase: 'saved-passphrase-value',
    );
    await _settlePage(tester, storage);

    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);
    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsOneWidget);
    expect(find.text('Thay đổi key'), findsOneWidget);
    expect(find.text('saved-api-value'), findsNothing);
    expect(find.text('saved-secret-value'), findsNothing);

    await _tap(
      tester,
      find.byKey(const Key('settings-change-okx-credentials')),
    );
    expect(
      find.byKey(const Key('settings-okx-credential-bundle')),
      findsOneWidget,
    );
    final bundleController = tester
        .widget<TextFormField>(
          find.byKey(const Key('settings-okx-credential-bundle')),
        )
        .controller!;
    expect(bundleController.text, isEmpty);
    const pendingEditorText = 'unsaved editor contents';
    await tester.enterText(
      find.byKey(const Key('settings-okx-credential-bundle')),
      pendingEditorText,
    );

    await _tap(tester, find.byTooltip('Làm mới dữ liệu'));
    expect(bundleController.text, pendingEditorText);
    expect(
      find.byKey(const Key('settings-okx-credential-bundle')),
      findsOneWidget,
    );

    await _tap(
      tester,
      find.byKey(const Key('settings-cancel-okx-replacement')),
    );
    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsOneWidget);
    expect(storage.saveCalls, 0);
    expect(bundleController.text, isEmpty);
    expect(storage.apiKey, 'saved-api-value');
    expect(storage.secretKey, 'saved-secret-value');
    expect(storage.passphrase, 'saved-passphrase-value');

    await tester.pumpWidget(const SizedBox.shrink());
    await _settlePage(tester, storage);
    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsOneWidget);
  });

  testWidgets(
    'API summary refresh discards a stale read after editing starts',
    (tester) async {
      final storage = _FakeStorage(
        apiKey: 'saved-api',
        secretKey: 'saved-secret',
        passphrase: 'saved-pass',
      );
      await _settlePage(tester, storage);

      final gate = Completer<void>();
      storage.loadGate = gate;
      storage.apiKey = null;
      storage.secretKey = null;
      storage.passphrase = null;
      await _tap(tester, find.byTooltip('Làm mới dữ liệu'));
      await tester.pump();
      storage.apiKey = 'saved-api';
      storage.secretKey = 'saved-secret';
      storage.passphrase = 'saved-pass';

      await _tap(
        tester,
        find.byKey(const Key('settings-change-okx-credentials')),
      );
      gate.complete();
      await tester.pump();
      await tester.pump();

      await _tap(
        tester,
        find.byKey(const Key('settings-cancel-okx-replacement')),
      );
      expect(find.text('Đã lưu thông tin API trên thiết bị'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('pastes multiline credentials and saves exact trimmed values', (
    tester,
  ) async {
    final storage = _FakeStorage();
    final pasted =
        'API Key: demo-api\nSecret Key = demo:secret=tail\n'
        'Passphrase: demo-pass';
    var clipboardReads = 0;
    _mockClipboard(
      () async => {'text': pasted},
      onRead: () => clipboardReads++,
    );
    await _settlePage(tester, storage);

    final bundleField = find.byKey(const Key('settings-okx-credential-bundle'));
    final inputField = tester.widget<TextField>(
      find.descendant(of: bundleField, matching: find.byType(TextField)),
    );
    expect(inputField.obscureText, isTrue);
    expect(inputField.maxLines, 1);
    expect(clipboardReads, 0);
    await _tap(tester, find.byKey(const Key('settings-paste-okx-clipboard')));
    await tester.pumpAndSettle();
    expect(clipboardReads, 1);
    expect(tester.widget<TextFormField>(bundleField).controller!.text, pasted);
    final bundleController = tester
        .widget<TextFormField>(bundleField)
        .controller!;
    await _tap(tester, find.byKey(const Key('settings-save-okx-credentials')));
    await tester.pumpAndSettle();

    expect(storage.saves, [
      {
        'apiKey': 'demo-api',
        'secretKey': 'demo:secret=tail',
        'passphrase': 'demo-pass',
      },
    ]);
    expect(bundleController.text, isEmpty);
    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsOneWidget);
    expect(find.text('demo:secret=tail'), findsNothing);
  });

  testWidgets(
    'rejects malformed, duplicate, and missing bundles without writes',
    (tester) async {
      final storage = _FakeStorage();
      var clipboardText = '';
      _mockClipboard(() async => {'text': clipboardText});
      await _settlePage(tester, storage);
      final bundleField = find.byKey(
        const Key('settings-okx-credential-bundle'),
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: bundleField,
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      const invalidInputs = [
        'API Key: DO_NOT_ECHO\nAPI Key: second\n'
            'Secret Key: secret\nPassphrase: pass',
        'API Key: api\nSecret Key: secret',
        'unlabeled DO_NOT_ECHO',
        'API Key: api\nSecret Key: secret\nPassphrase: pass\nextra text',
      ];

      for (final input in invalidInputs) {
        clipboardText = input;
        await _tap(
          tester,
          find.byKey(const Key('settings-paste-okx-clipboard')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(bundleField).controller!.text,
          input,
        );
        await _tap(
          tester,
          find.byKey(const Key('settings-save-okx-credentials')),
        );
        await tester.pump();
        expect(
          find.byWidgetPredicate((widget) {
            if (widget is Text) {
              return widget.data?.contains('DO_NOT_ECHO') ??
                  widget.textSpan?.toPlainText().contains('DO_NOT_ECHO') ??
                  false;
            }
            return widget is RichText &&
                widget.text.toPlainText().contains('DO_NOT_ECHO');
          }),
          findsNothing,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('settings-okx-input-error')))
              .data,
          'Thông tin API không hợp lệ.',
        );
        expect(storage.saveCalls, 0);
      }
    },
  );

  testWidgets(
    'pending clipboard read disables editing and keeps multiline text',
    (tester) async {
      final storage = _FakeStorage(
        apiKey: 'saved-api',
        secretKey: 'saved-secret',
        passphrase: 'saved-pass',
      );
      final clipboardReply = Completer<Object?>();
      _mockClipboard(() => clipboardReply.future);
      await _settlePage(tester, storage);
      await _tap(
        tester,
        find.byKey(const Key('settings-change-okx-credentials')),
      );
      await _tap(tester, find.byKey(const Key('settings-paste-okx-clipboard')));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('settings-trade-access-manual-refresh')),
            )
            .onPressed,
        isNull,
      );

      final bundleField = find.byKey(
        const Key('settings-okx-credential-bundle'),
      );
      expect(tester.widget<TextFormField>(bundleField).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('settings-toggle-okx-entry-mode')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('settings-cancel-okx-replacement')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('settings-save-okx-credentials')),
            )
            .onPressed,
        isNull,
      );

      const pasted = 'API Key: api\nSecret Key: secret\nPassphrase: pass';
      clipboardReply.complete({'text': pasted});
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(bundleField).controller!.text,
        pasted,
      );
      expect(storage.saveCalls, 0);
    },
  );

  testWidgets('clipboard failure keeps the draft and hides platform details', (
    tester,
  ) async {
    final storage = _FakeStorage();
    _mockClipboard(() async {
      throw PlatformException(
        code: 'clipboard-error',
        message: 'DO_NOT_ECHO platform detail',
      );
    });
    await _settlePage(tester, storage);
    final bundleField = find.byKey(const Key('settings-okx-credential-bundle'));
    const draft =
        '{"apiKey":"draft-api","secretKey":"draft-secret",'
        '"passphrase":"draft-pass"}';
    await tester.enterText(bundleField, draft);
    await _tap(tester, find.byKey(const Key('settings-paste-okx-clipboard')));
    await tester.pumpAndSettle();

    expect(
      find.text('Không thể đọc clipboard. Hãy sao chép lại rồi thử.'),
      findsOneWidget,
    );
    expect(find.textContaining('DO_NOT_ECHO platform detail'), findsNothing);
    expect(tester.widget<TextFormField>(bundleField).controller!.text, draft);
    expect(storage.saveCalls, 0);
  });

  testWidgets('manual entry is available and saves the three required values', (
    tester,
  ) async {
    final storage = _FakeStorage();
    await _settlePage(tester, storage);
    await _tap(tester, find.byKey(const Key('settings-toggle-okx-entry-mode')));

    final apiField = find.byKey(const Key('settings-okx-api-key'));
    final secretField = find.byKey(const Key('settings-okx-secret-key'));
    final passphraseField = find.byKey(const Key('settings-okx-passphrase'));
    await _tap(tester, find.byKey(const Key('settings-save-okx-credentials')));
    expect(storage.saveCalls, 0);
    expect(find.text('Không được để trống'), findsNWidgets(3));

    await tester.enterText(apiField, 'manual-api');
    await tester.enterText(secretField, 'manual-secret');
    await tester.enterText(passphraseField, 'manual-pass');
    await _tap(tester, find.byKey(const Key('settings-save-okx-credentials')));
    await tester.pumpAndSettle();

    expect(storage.saves.single, {
      'apiKey': 'manual-api',
      'secretKey': 'manual-secret',
      'passphrase': 'manual-pass',
    });
    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsOneWidget);
  });

  testWidgets('switching entry modes clears unsaved values', (tester) async {
    final storage = _FakeStorage();
    await _settlePage(tester, storage);
    await tester.enterText(
      find.byKey(const Key('settings-okx-credential-bundle')),
      'API Key: temporary',
    );
    await _tap(tester, find.byKey(const Key('settings-toggle-okx-entry-mode')));

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('settings-okx-api-key')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('settings-okx-api-key')),
      'temporary-manual',
    );
    await _tap(tester, find.byKey(const Key('settings-toggle-okx-entry-mode')));
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('settings-okx-credential-bundle')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(storage.saveCalls, 0);
  });

  testWidgets('incomplete saved credentials leave the editor available', (
    tester,
  ) async {
    final storage = _FakeStorage(apiKey: 'partial-api');
    await _settlePage(tester, storage);

    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsNothing);
    expect(
      find.byKey(const Key('settings-okx-credential-bundle')),
      findsOneWidget,
    );
    expect(storage.saveCalls, 0);
  });

  testWidgets('pending load blocks entry until the read completes', (
    tester,
  ) async {
    final loadGate = Completer<void>();
    final storage = _FakeStorage(loadGate: loadGate);
    await tester.pumpWidget(_settingsPage(storage));
    await tester.pump();

    expect(find.text('Đang tải thông tin API đã lưu…'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-okx-credential-bundle')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings-save-okx-credentials')),
      findsNothing,
    );
    expect(storage.saveCalls, 0);

    loadGate.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-okx-credential-bundle')),
      findsOneWidget,
    );
  });

  testWidgets('load failure is generic and retry restores the editor', (
    tester,
  ) async {
    final storage = _FakeStorage()..failLoad = true;
    await _settlePage(tester, storage);

    expect(
      find.text('Không thể tải thông tin API đã lưu. Hãy thử lại.'),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic load failure'), findsNothing);
    expect(
      find.byKey(const Key('settings-save-okx-credentials')),
      findsNothing,
    );
    expect(storage.saveCalls, 0);

    storage.failLoad = false;
    await _tap(
      tester,
      find.byKey(const Key('settings-retry-load-okx-credentials')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-okx-credential-bundle')),
      findsOneWidget,
    );
    expect(storage.saveCalls, 0);
  });

  testWidgets('pending save disables input, mode, cancel, and save controls', (
    tester,
  ) async {
    final storage = _FakeStorage(
      apiKey: 'saved-api',
      secretKey: 'saved-secret',
      passphrase: 'saved-pass',
      saveGate: Completer<void>(),
    );
    await _settlePage(tester, storage);
    await _tap(
      tester,
      find.byKey(const Key('settings-change-okx-credentials')),
    );
    final bundleField = find.byKey(const Key('settings-okx-credential-bundle'));
    await tester.enterText(
      bundleField,
      '{"apiKey":"next-api","secretKey":"next-secret",'
      '"passphrase":"next-pass"}',
    );
    await _tap(tester, find.byKey(const Key('settings-save-okx-credentials')));
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('settings-trade-access-manual-refresh')),
          )
          .onPressed,
      isNull,
    );

    expect(tester.widget<TextFormField>(bundleField).enabled, isFalse);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('settings-toggle-okx-entry-mode')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('settings-cancel-okx-replacement')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('settings-save-okx-credentials')),
          )
          .onPressed,
      isNull,
    );

    storage.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsOneWidget);
  });

  testWidgets('save failure retains input and hides the exception', (
    tester,
  ) async {
    final storage = _FakeStorage()..failSave = true;
    await _settlePage(tester, storage);
    final bundleField = find.byKey(const Key('settings-okx-credential-bundle'));
    const pasted =
        '{"apiKey":"demo-api","secretKey":"DO_NOT_ECHO",'
        '"passphrase":"demo-pass"}';
    await tester.enterText(bundleField, pasted);
    await _tap(tester, find.byKey(const Key('settings-save-okx-credentials')));
    await tester.pumpAndSettle();

    expect(
      find.text('Không thể lưu thông tin API. Hãy thử lại.'),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic save failure'), findsNothing);
    expect(tester.widget<TextFormField>(bundleField).controller!.text, pasted);
    expect(storage.saveCalls, 1);
    expect(find.text('Đã lưu thông tin API trên thiết bị'), findsNothing);
  });

  testWidgets('async load and save completion after disposal is safe', (
    tester,
  ) async {
    final loadGate = Completer<void>();
    final loadStorage = _FakeStorage(loadGate: loadGate);
    await tester.pumpWidget(_settingsPage(loadStorage));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    loadGate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);

    final saveGate = Completer<void>();
    final saveStorage = _FakeStorage(saveGate: saveGate);
    await _settlePage(tester, saveStorage);
    await tester.enterText(
      find.byKey(const Key('settings-okx-credential-bundle')),
      '{"apiKey":"api","secretKey":"secret","passphrase":"pass"}',
    );
    await _tap(tester, find.byKey(const Key('settings-save-okx-credentials')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    saveGate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard completion after navigation is ignored', (
    tester,
  ) async {
    final storage = _FakeStorage();
    final clipboardReply = Completer<Object?>();
    _mockClipboard(() => clipboardReply.future);
    await _settlePage(tester, storage);
    await _tap(tester, find.byKey(const Key('settings-paste-okx-clipboard')));
    await tester.pumpWidget(const SizedBox.shrink());
    clipboardReply.complete({
      'text': 'API Key: api\nSecret Key: secret\nPassphrase: pass',
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
