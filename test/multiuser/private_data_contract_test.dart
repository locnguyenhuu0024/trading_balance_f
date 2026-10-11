import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/network/foreground_read_gate.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';
import 'package:trading_balance_f/core/session/connection_scope.dart';
import 'package:trading_balance_f/core/session/user_session.dart';
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/features/connections/data/multi_user_api_client.dart';
import 'package:trading_balance_f/features/connections/domain/connection_models.dart';
import 'package:trading_balance_f/features/connections/presentation/private_data_screens.dart';
import 'package:trading_balance_f/features/connections/presentation/providers/multi_user_provider.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart'
    show hideBalanceProvider, isDarkModeProvider;

void main() {
  test(
    'isolated overview reader passes real v2 scope guards without selection mutation',
    () async {
      final sessions = UserSessionStore(initialSession: _session());
      final selectedScopes = ConnectionScopeStore();
      final selectedBefore = selectedScopes.select(
        session: sessions.current!,
        connectionId: 'conn_demo_001',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SWAP',
        credentialVersion: 1,
        permissionVersion: 1,
      )!;
      final adapter = _OverviewBoundaryAdapter();
      final backend = BackendDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://fixture.example/gateway',
        isWeb: false,
      );
      final api = MultiUserApiClient(
        backend: backend,
        sessions: sessions,
        scopes: selectedScopes,
        isWeb: false,
      );
      final connections = await api.getConnections();
      final isolatedScopes = ConnectionScopeStore();
      final projectionSessions = UserSessionStore(
        initialSession: sessions.current,
      );
      final reader = api.createReadOnlyScopeReader(
        isolatedScopes,
        isolatedSessions: projectionSessions,
      );

      for (final connection in connections) {
        final scope = isolatedScopes.select(
          session: projectionSessions.current!,
          connectionId: connection.connectionId,
          exchange: connection.exchange,
          environment: connection.environment,
          region: connection.region,
          product: 'SPOT',
          credentialVersion: connection.credentialVersion,
          permissionVersion: connection.permissionVersion,
        )!;
        final result = await reader.balances(scope, limit: 100);
        expect(result.scope.sameAuthority(scope), isTrue);
        expect(result.page.rows.single.asset, 'USDT');
      }

      expect(adapter.balanceConnectionIds, ['conn_demo_001', 'conn_demo_002']);
      expect(adapter.methods, everyElement('GET'));
      expect(
        adapter.paths.where((path) => path.contains('/actions/')),
        isEmpty,
      );
      expect(selectedScopes.current, same(selectedBefore));

      backend.close(force: true);
      isolatedScopes.dispose();
      projectionSessions.dispose();
      selectedScopes.dispose();
      sessions.dispose();
    },
  );

  test(
    'secondary account late 401 cannot clear replacement session or scope',
    () async {
      final sessions = UserSessionStore(initialSession: _session());
      final selectedScopes = ConnectionScopeStore();
      selectedScopes.select(
        session: sessions.current!,
        connectionId: 'conn_demo_001',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      );
      final adapter = _OverviewBoundaryAdapter(
        unauthorizedConnectionId: 'conn_demo_002',
        holdUnauthorizedResponse: true,
      );
      final backend = BackendDataClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://fixture.example/gateway',
        isWeb: false,
        onV2Unauthorized: (owner, generation, expected) {
          if (identical(owner, sessions) &&
              sessions.matches(generation, expected)) {
            sessions.update(null);
          }
        },
      );
      final api = MultiUserApiClient(
        backend: backend,
        sessions: sessions,
        scopes: selectedScopes,
        isWeb: false,
      );
      final isolatedScopes = ConnectionScopeStore();
      final projectionSessions = UserSessionStore(
        initialSession: sessions.current,
      );
      final reader = api.createReadOnlyScopeReader(
        isolatedScopes,
        isolatedSessions: projectionSessions,
      );
      final scopeA = isolatedScopes.select(
        session: projectionSessions.current!,
        connectionId: 'conn_demo_002',
        exchange: 'BINANCE',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      )!;

      final request = reader.balances(scopeA, limit: 100);
      await adapter.unauthorizedRequestStarted.future;
      final replacement = UserSession(
        userId: 'user-b',
        username: 'bob',
        sessionId: 'session-b',
        mode: 'ordinary',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        bearerToken: 'opaque-b',
      );
      sessions.update(replacement);
      final scopeB = selectedScopes.select(
        session: replacement,
        connectionId: 'conn_demo_001',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SWAP',
        credentialVersion: 2,
        permissionVersion: 2,
      )!;
      adapter.releaseUnauthorizedResponse();
      await expectLater(request, throwsA(isA<BackendDataException>()));

      expect(sessions.current?.sessionId, 'session-b');
      expect(selectedScopes.current, same(scopeB));
      expect(selectedScopes.matches(scopeB.generation, scopeB), isTrue);

      backend.close(force: true);
      isolatedScopes.dispose();
      projectionSessions.dispose();
      selectedScopes.dispose();
      sessions.dispose();
    },
  );

  test('disposed overview suppresses a late final-page error result', () async {
    final harness = _Harness(
      connections: [_connection('conn_demo_001', 'OKX', 'A account')],
    );
    final key = 'conn_demo_001:FUTURES';
    harness.api.overviewBlockedFor = key;
    harness.api.overviewThrowsFor = key;
    harness.api.overviewGate = Completer<void>();
    harness.api.overviewRequestStarted = Completer<void>();
    harness.api.overviewRequestReturned = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        userSessionStoreProvider.overrideWith((ref) => harness.sessions),
        connectionScopeStoreProvider.overrideWith((ref) => harness.scopes),
        multiUserApiClientProvider.overrideWith((ref) => harness.api),
      ],
    );
    AsyncValue<MultiAccountBalanceOverview>? observed;
    container.listen<AsyncValue<MultiAccountBalanceOverview>>(
      multiAccountBalanceOverviewProvider,
      (_, next) => observed = next,
      fireImmediately: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      harness.api.overviewRequestStarted!.isCompleted,
      isTrue,
      reason: 'Overview provider state: $observed',
    );
    expect(harness.api.overviewRequests, hasLength(4));

    container.dispose();
    harness.api.overviewGate!.complete();
    await harness.api.overviewRequestReturned!.future.timeout(
      const Duration(seconds: 2),
    );
    await Future<void>.delayed(Duration.zero);

    expect(observed?.hasValue, isNot(true));
    expect(harness.api.overviewRequests, hasLength(4));
    harness.dispose();
  });

  testWidgets('partially filled OKX limit remains cancelable by exact identity', (
    tester,
  ) async {
    final harness = _Harness(
      order: const NormalizedOrder(
        exchange: 'OKX',
        product: 'SWAP',
        environment: 'demo',
        region: 'global',
        orderId: 'order-native-77',
        instrument: 'BTC-USDT-SWAP',
        side: 'buy',
        orderType: 'limit',
        status: 'partially_filled',
        nativeQuantity: '5',
        quantityUnit: 'contracts',
        averagePrice: '320',
        limitPrice: '321.5',
        filledQuantity: '2',
        eventTime: null,
        nativeAsset: 'BTC',
        filledQuantityUnit: 'contracts',
        clientOrderId: 'client-a-1',
        metadataVersion: 'orders-v4',
      ),
    );
    await _pumpOrders(tester, harness);
    await tester.tap(find.text('Lệnh'));
    await tester.pumpAndSettle();

    final cancel = find.byKey(const Key('cancel-order-order-native-77-0'));
    expect(cancel, findsOneWidget);
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('Hủy lệnh limit'), findsOneWidget);
    expect(
      find.text(
        'Số lượng gốc 5 contracts · Đã khớp 2 contracts · Giá giới hạn 321.5 · Giá khớp 320',
      ),
      findsOneWidget,
    );
    expect(find.text('Số lượng gốc: 5 contracts'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prepared-action-confirm')));
    await tester.pumpAndSettle();

    expect(harness.api.lastAction, 'cancel_order');
    expect(harness.api.lastTargetIdentity, {
      'instType': 'SWAP',
      'instId': 'BTC-USDT-SWAP',
      'ordId': 'order-native-77',
      'ordType': 'limit',
      'side': 'buy',
      'px': '321.5',
      'sz': '5',
    });
    expect(harness.pending.operations.single.status, 'SENDING');
    expect(find.textContaining('Mục tiêu 1 · ATTEMPT_STARTED'), findsOneWidget);
    await _close(tester, harness);
  });

  testWidgets(
    'accepted delayed action survives route disposal and same-owner authority changes only on original scope',
    (tester) async {
      final harness = _Harness(position: _position());
      harness.api.executeGate = Completer<void>();
      harness.api.executeRequestStarted = Completer<void>();
      await _pumpOrders(tester, harness, useProviderPendingStore: true);

      final pageContext = tester.element(find.byType(MultiUserOrdersScreen));
      final navigator = Navigator.of(pageContext);
      final container = ProviderScope.containerOf(pageContext, listen: false);
      final pending = container.read(pendingOperationStoreProvider);
      expect(pending.operations, isEmpty);

      await tester.tap(find.byKey(const Key('close-position-BTC-USDT-SWAP-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prepared-action-confirm')));
      await tester.pump();
      await harness.api.executeRequestStarted!.future.timeout(
        const Duration(seconds: 2),
      );

      navigator.pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MultiUserOrdersScreen), findsNothing);

      final originalOwner = harness.sessions.current!;
      harness.sessions.update(
        originalOwner.withStepUp(
          DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      final replacementScope = harness.scopes.select(
        session: harness.sessions.current!,
        connectionId: 'conn_demo_002',
        exchange: 'BINANCE',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      )!;
      harness.selected.select(
        _connection('conn_demo_002', 'BINANCE', 'B account'),
      );
      expect(replacementScope.connectionId, 'conn_demo_002');

      final stored = Completer<void>();
      void observeStoredOperation() {
        if (pending.operations.isNotEmpty && !stored.isCompleted) {
          stored.complete();
        }
      }

      pending.addListener(observeStoredOperation);
      harness.api.executeGate!.complete();
      await stored.future.timeout(const Duration(seconds: 2));
      pending.removeListener(observeStoredOperation);

      expect(pending.operations, hasLength(1));
      expect(pending.operations.single.scope, harness.scope);
      expect(pending.operations.single.scope.connectionId, 'conn_demo_001');
      expect(pending.operations.single.scope.product, 'SWAP');
      expect(pending.operations.single.connectionLabel, 'A account');
      expect(pending.operations.single.status, 'SENDING');

      harness.sessions.update(null);
      expect(pending.operations, isEmpty);
      harness.sessions.update(
        UserSession(
          userId: 'user-b',
          username: 'bob',
          sessionId: 'session-b',
          mode: 'ordinary',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          bearerToken: 'opaque-b',
        ),
      );
      expect(pending.operations, isEmpty);

      await _close(tester, harness);
    },
  );

  testWidgets(
    'delayed accepted receipt is discarded when another login replaces its owner',
    (tester) async {
      final harness = _Harness(position: _position());
      harness.api.executeGate = Completer<void>();
      harness.api.executeRequestStarted = Completer<void>();
      harness.api.executeRequestReturned = Completer<void>();
      await _pumpOrders(tester, harness, useProviderPendingStore: true);
      final pageContext = tester.element(find.byType(MultiUserOrdersScreen));
      final pending = ProviderScope.containerOf(
        pageContext,
        listen: false,
      ).read(pendingOperationStoreProvider);

      await tester.tap(find.byKey(const Key('close-position-BTC-USDT-SWAP-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prepared-action-confirm')));
      await tester.pump();
      await harness.api.executeRequestStarted!.future.timeout(
        const Duration(seconds: 2),
      );
      expect(harness.api.executeCalls, 1);
      expect(pending.operations, isEmpty);

      harness.sessions.update(null);
      harness.sessions.update(
        UserSession(
          userId: 'user-b',
          username: 'bob',
          sessionId: 'session-b',
          mode: 'ordinary',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          bearerToken: 'opaque-b',
        ),
      );
      harness.scopes.select(
        session: harness.sessions.current!,
        connectionId: 'conn_demo_002',
        exchange: 'BINANCE',
        environment: 'demo',
        region: 'global',
        product: 'USD_M',
        credentialVersion: 1,
        permissionVersion: 1,
      );
      harness.selected.select(
        _connection('conn_demo_002', 'BINANCE', 'B account'),
      );
      harness.api.executeGate!.complete();
      await harness.api.executeRequestReturned!.future.timeout(
        const Duration(seconds: 2),
      );
      await tester.pump();

      expect(harness.api.executeCalls, 1);
      expect(harness.api.operationResultCalls, 0);
      expect(pending.operations, isEmpty);
      await _close(tester, harness);
    },
  );

  testWidgets(
    'UNKNOWN action lookup keeps one send attempt and records proof without resubmission',
    (tester) async {
      final harness = _Harness(position: _position());
      harness.api.executeThrows = true;
      harness.api.resultStatus = 'UNKNOWN';
      await _pumpOrders(tester, harness);

      await tester.tap(find.byKey(const Key('close-position-BTC-USDT-SWAP-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prepared-action-confirm')));
      await tester.pumpAndSettle();

      expect(harness.api.prepareCalls, 1);
      expect(harness.api.executeCalls, 1);
      expect(harness.api.operationResultCalls, 1);
      expect(harness.pending.operations, hasLength(1));
      expect(harness.pending.operations.single.status, 'UNKNOWN');
      await tester.pump(const Duration(seconds: 5));
      expect(harness.api.executeCalls, 1);
      expect(harness.api.prepareCalls, 1);
      await _close(tester, harness);
    },
  );

  testWidgets(
    'saved connection step-up enables a supported action without creating a connection',
    (tester) async {
      final harness = _Harness(position: _position());
      final owner = harness.sessions.current!;
      harness.sessions.update(
        owner.withStepUp(DateTime.now().subtract(const Duration(seconds: 1))),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionStoreProvider.overrideWith((ref) => harness.sessions),
            connectionScopeStoreProvider.overrideWith((ref) => harness.scopes),
            selectedConnectionProvider.overrideWith((ref) => harness.selected),
            pendingOperationStoreProvider.overrideWith(
              (ref) => harness.pending,
            ),
            multiUserApiClientProvider.overrideWith((ref) => harness.api),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const MultiUserConnectionContextStrip(),
                    FilledButton(
                      key: const Key('open-saved-account-orders'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const MultiUserOrdersScreen(),
                        ),
                      ),
                      child: const Text('Mở lệnh tài khoản đã lưu'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.sessions.current?.canTrade, isFalse);
      expect(find.byKey(const Key('verify-trade-step-up')), findsOneWidget);

      await tester.tap(find.byKey(const Key('verify-trade-step-up')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Xác minh lại'), findsOneWidget);
      final submit = find.widgetWithText(FilledButton, 'Xác minh');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'saved-password',
      );
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(1), '123456');
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller
            ?.text,
        'saved-password',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller
            ?.text,
        '123456',
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(harness.api.stepUpCalls, 1);
      expect(harness.sessions.current?.canTrade, isTrue);
      expect(harness.api.createConnectionCalls, 0);
      await tester.tap(find.byKey(const Key('open-saved-account-orders')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('close-position-BTC-USDT-SWAP-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prepared-action-confirm')));
      await tester.pumpAndSettle();

      expect(harness.api.prepareCalls, 1);
      expect(harness.api.lastAction, 'close_position');
      expect(harness.api.createConnectionCalls, 0);
      await _close(tester, harness);
    },
  );

  testWidgets('SWAP native ccy does not become a margin action field', (
    tester,
  ) async {
    final harness = _Harness(
      position: _position(marginCurrency: 'USDT', positionId: null),
    );
    await _pumpOrders(tester, harness);

    final close = find.byKey(const Key('close-position-BTC-USDT-SWAP-0'));
    expect(close, findsOneWidget);
    expect(tester.widget<TextButton>(close).onPressed, isNotNull);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.textContaining('Số lượng gốc: 3 contracts'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prepared-action-confirm')));
    await tester.pumpAndSettle();

    expect(harness.api.lastAction, 'close_position');
    expect(harness.api.lastTargetIdentity, {
      'instrumentType': 'SWAP',
      'instrumentId': 'BTC-USDT-SWAP',
      'positionSide': 'long',
      'marginMode': 'cross',
    });
    expect(
      harness.api.lastTargetIdentity!.containsKey('marginCurrency'),
      isFalse,
    );
    await _close(tester, harness);
  });

  testWidgets(
    'net short signed contracts allow close without optional posCcy',
    (tester) async {
      final harness = _Harness(
        position: _position(
          nativeQuantity: '-3',
          nativeAsset: null,
          side: 'net',
        ),
      );
      await _pumpOrders(tester, harness);

      final close = find.byKey(const Key('close-position-BTC-USDT-SWAP-0'));
      expect(tester.widget<TextButton>(close).onPressed, isNotNull);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Số lượng gốc: -3 contracts'), findsOneWidget);
      await tester.tap(find.byKey(const Key('prepared-action-confirm')));
      await tester.pumpAndSettle();
      expect(harness.api.prepareCalls, 1);
      expect(harness.api.lastAction, 'close_position');
      expect(harness.api.lastTargetIdentity?['positionSide'], 'net');
      await _close(tester, harness);
    },
  );

  testWidgets('OKX market-buy quote budget preserves native USDT units', (
    tester,
  ) async {
    final harness = _Harness(
      selectedProduct: 'SPOT',
      order: const NormalizedOrder(
        exchange: 'OKX',
        product: 'SPOT',
        environment: 'demo',
        region: 'global',
        orderId: 'spot-market-quote-1',
        instrument: 'BTC-USDT',
        side: 'buy',
        orderType: 'market',
        status: 'filled',
        nativeQuantity: '100',
        quantityUnit: null,
        averagePrice: '50000',
        limitPrice: null,
        filledQuantity: '0.002',
        eventTime: null,
        nativeAsset: 'USDT',
        filledQuantityUnit: 'base',
        clientOrderId: 'client-quote-budget',
        metadataVersion: 'orders-v4',
      ),
    );
    await _pumpOrders(tester, harness);
    await tester.tap(find.text('Lệnh'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Số lượng gốc 100 USDT · Đã khớp 0.002 base'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cancel-order-spot-market-quote-1-0')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('cancel-order-spot-market-quote-1-0')),
          )
          .onPressed,
      isNull,
    );
    expect(harness.api.prepareCalls, 0);
    await _close(tester, harness);
  });

  testWidgets(
    'inconsistent contract units disable order and position actions',
    (tester) async {
      final harness = _Harness(
        position: _position(quantityUnit: null),
        order: const NormalizedOrder(
          exchange: 'OKX',
          product: 'SWAP',
          environment: 'demo',
          region: 'global',
          orderId: 'bad-units-order',
          instrument: 'BTC-USDT-SWAP',
          side: 'buy',
          orderType: 'limit',
          status: 'partially_filled',
          nativeQuantity: '5',
          quantityUnit: null,
          averagePrice: '320',
          limitPrice: '321.5',
          filledQuantity: '2',
          eventTime: null,
          nativeAsset: 'USDT',
          filledQuantityUnit: 'base',
          clientOrderId: 'bad-units-client',
          metadataVersion: 'orders-v4',
        ),
      );
      await _pumpOrders(tester, harness);

      final close = find.byKey(const Key('close-position-BTC-USDT-SWAP-0'));
      expect(close, findsNothing);
      expect(
        find.text('Thiếu định danh gốc; thao tác bị khóa.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Lệnh'));
      await tester.pumpAndSettle();
      final cancel = find.byKey(const Key('cancel-order-bad-units-order-0'));
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      expect(harness.api.prepareCalls, 0);
      await _close(tester, harness);
    },
  );

  testWidgets('stale metadata blocks position preparation', (tester) async {
    final harness = _Harness(position: _position(), complete: false);
    await _pumpOrders(tester, harness);

    final close = find.byKey(const Key('close-position-BTC-USDT-SWAP-0'));
    expect(tester.widget<TextButton>(close).onPressed, isNull);
    expect(harness.api.prepareCalls, 0);
    await _close(tester, harness);
  });

  testWidgets(
    'close all enumerates unsupported rows and prepares one at a time',
    (tester) async {
      final unsupported = _position(
        product: 'MARGIN',
        instrument: 'BTC-USDT',
        marginCurrency: null,
        positionId: 'margin-1',
      );
      final harness = _Harness(
        positions: [_position(), unsupported],
        selectedProduct: 'SWAP',
      );
      await _pumpOrders(tester, harness);

      final closeAll = find.byKey(const Key('close-all-supported-positions'));
      expect(tester.widget<FilledButton>(closeAll).onPressed, isNotNull);
      await tester.tap(closeAll);
      await tester.pumpAndSettle();
      expect(find.text('Hỗ trợ đóng: 1 · Giữ nguyên: 1'), findsOneWidget);
      expect(
        find.text('BTC-USDT · MARGIN · long · không đủ định danh cho thao tác'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('close-all-review-each')));
      await tester.pumpAndSettle();
      expect(harness.api.prepareCalls, 1);
      expect(find.textContaining('Đóng vị thế BTC-USDT-SWAP'), findsOneWidget);
      await tester.tap(find.text('Hủy').last);
      await tester.pumpAndSettle();
      expect(harness.api.prepareCalls, 1);
      await _close(tester, harness);
    },
  );

  testWidgets(
    'pending panel keeps PARTIAL target result and never treats it as success',
    (tester) async {
      final harness = _Harness(position: _position());
      harness.pending.add(
        PendingOperation(
          scope: harness.scope,
          operationId: 'operation_0001',
          action: 'close_position',
          createdAt: DateTime.now().toUtc(),
          connectionLabel: 'A account',
          status: 'UNKNOWN',
          targets: const [
            {
              'index': 0,
              'status': 'ATTEMPT_STARTED',
              'result': {'positionVerified': false},
            },
          ],
        ),
      );
      harness.api.resultStatus = 'PARTIAL';
      await _pumpOrders(tester, harness);

      expect(find.textContaining('A account · SWAP'), findsOneWidget);
      expect(
        find.textContaining('Mục tiêu 1 · ATTEMPT_STARTED'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tra cứu'));
      await tester.pumpAndSettle();

      expect(harness.pending.operations, hasLength(1));
      expect(harness.pending.operations.single.status, 'PARTIAL');
      expect(find.textContaining('reason: partial outcome'), findsOneWidget);
      await _close(tester, harness);
    },
  );

  testWidgets(
    'portfolio coalesces foreground polling and keeps 500 balances lazy',
    (tester) async {
      final harness = _Harness(position: _position());
      await _pumpPortfolio(tester, harness);
      expect(harness.api.balanceCalls, 1);
      expect(harness.api.positionCalls, 1);
      expect(harness.api.orderCalls, 1);
      expect(find.text('ASSET-499'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(harness.api.positionCalls, greaterThanOrEqualTo(2));
      expect(harness.api.orderCalls, greaterThanOrEqualTo(2));
      expect(harness.api.balanceCalls, 1);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(harness.api.balanceCalls, greaterThanOrEqualTo(2));

      final countsBeforeBackground = [
        harness.api.balanceCalls,
        harness.api.positionCalls,
        harness.api.orderCalls,
      ];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect([
        harness.api.balanceCalls,
        harness.api.positionCalls,
        harness.api.orderCalls,
      ], countsBeforeBackground);
      await _close(tester, harness);
    },
  );

  testWidgets(
    'initially paused portfolio starts no reads and resumes one coalesced snapshot',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final harness = _Harness(position: _position());
      await _pumpPortfolio(tester, harness);

      expect(harness.api.balanceCalls, 0);
      expect(harness.api.positionCalls, 0);
      expect(harness.api.orderCalls, 0);
      await tester.pump(const Duration(seconds: 20));
      expect(harness.api.balanceCalls, 0);
      expect(harness.api.positionCalls, 0);
      expect(harness.api.orderCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(harness.api.balanceCalls, 1);
      expect(harness.api.positionCalls, 1);
      expect(harness.api.orderCalls, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(harness.api.balanceCalls, 1);
      expect(harness.api.positionCalls, 1);
      expect(harness.api.orderCalls, 1);

      await _close(tester, harness);
    },
  );

  testWidgets(
    'paused transient failure backoff sends no background retry and resumes once',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final harness = _Harness(position: _position());
      harness.api.transientPositionFailuresRemaining = 1;
      var clock = DateTime.now();
      final readGate = ForegroundReadGate(now: () => clock);
      await _pumpPortfolio(tester, harness, readGate: readGate);
      expect(harness.api.positionCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      expect(harness.api.positionCalls, 1);
      clock = clock.add(const Duration(seconds: 12));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(harness.api.positionCalls, 2);
      await tester.pump(const Duration(seconds: 3));
      expect(harness.api.positionCalls, 2);

      await _close(tester, harness);
    },
  );

  testWidgets(
    'pause cancels an in-flight private read and resume starts one fresh snapshot',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final harness = _Harness(position: _position());
      harness.api.positionGate = Completer<void>();
      harness.api.positionRequestStarted = Completer<void>();
      final readGate = ForegroundReadGate();
      await _pumpPortfolio(tester, harness, readGate: readGate, settle: false);
      await tester.pump();

      await harness.api.positionRequestStarted!.future.timeout(
        const Duration(seconds: 2),
      );
      expect(harness.api.positionCalls, 1);
      expect(harness.api.positionCancelTokens.single.isCancelled, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();
      expect(harness.api.positionCancelTokens.single.isCancelled, isTrue);

      await tester.pump(const Duration(seconds: 20));
      expect(harness.api.positionCalls, 1);
      expect(harness.api.balanceCalls, 1);
      expect(harness.api.orderCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(harness.api.positionCalls, 2);
      expect(harness.api.balanceCalls, 2);
      expect(harness.api.orderCalls, 2);

      await _close(tester, harness);
    },
  );

  testWidgets('hidden balance preference masks every normalized amount', (
    tester,
  ) async {
    final harness = _Harness(position: _position());
    await _pumpPortfolio(tester, harness, hidden: true);
    expect(find.text('102.00 USDT'), findsNothing);
    expect(find.textContaining('100.00'), findsNothing);
    expect(find.textContaining('2 USDT'), findsNothing);
    expect(find.text('••••••'), findsWidgets);
    await _close(tester, harness);
  });

  testWidgets(
    'combined overview is bounded read-only, preserves native units and partial proof',
    (tester) async {
      await tester.runAsync(_loadQaFonts);
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      final connections = [
        _connection('conn_demo_001', 'OKX', 'A account'),
        _connection('conn_demo_002', 'BINANCE', 'B account'),
      ];
      final harness = _Harness(position: _position(), connections: connections);
      harness.api.overviewNextCursorFor.add('conn_demo_002:USD_M');
      harness.api.overviewStaleFor.add('conn_demo_002:USD_M');
      harness.api.overviewUnavailableFor.add('conn_demo_002:SPOT');
      final selectedBefore = harness.scopes.current;
      final generationBefore = harness.scopes.generation;
      const overviewKey = ValueKey('qa-combined-overview-mixed-partial');
      await _pumpQaScreen(
        tester,
        harness,
        screen: const MultiUserPortfolioScreen(),
        mode: ThemeMode.light,
        textScale: 1,
        boundaryKey: overviewKey,
      );

      await tester.tap(find.byKey(const Key('toggle-combined-overview')));
      await tester.pumpAndSettle();

      expect(find.text('Tổng quan kết nối'), findsOneWidget);
      expect(
        find.text('Kết nối được xét 2/2 · Trang số dư đã yêu cầu 6.'),
        findsOneWidget,
      );
      expect(find.text('B account'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('overview-connection-conn_demo_001')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('overview-product-conn_demo_001-SPOT')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('100.00 USDT'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('overview-connection-conn_demo_002')),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('combined-balance-overview-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('overview-connection-conn_demo_002')),
      );
      await tester.tap(
        find.byKey(const Key('overview-connection-conn_demo_002')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('overview-product-conn_demo_002-SPOT')),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('combined-balance-overview-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('overview-product-conn_demo_002-SPOT')),
      );
      await tester.tap(
        find.byKey(const Key('overview-product-conn_demo_002-SPOT')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Không có snapshot số dư'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('overview-product-conn_demo_002-SPOT')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('overview-product-conn_demo_002-USD_M')),
      );
      await tester.tap(
        find.byKey(const Key('overview-product-conn_demo_002-USD_M')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Còn trang tiếp'), findsOneWidget);
      expect(find.textContaining('Snapshot cũ'), findsOneWidget);
      expect(find.textContaining('Tổng quy đổi chung'), findsNothing);
      expect(find.byKey(const Key('prepared-action-confirm')), findsNothing);
      await _saveQaPng(
        tester,
        overviewKey,
        'overview-mixed-partial-800-light.png',
      );
      expect(harness.api.overviewRequests, hasLength(6));
      expect(
        harness.api.overviewRequests.every((request) => request.limit == 100),
        isTrue,
      );
      expect(
        harness.api.overviewRequests.map((request) => request.scope.product),
        containsAll(['SPOT', 'MARGIN', 'SWAP', 'FUTURES', 'USD_M']),
      );
      expect(
        harness.api.overviewRequests.first.scope.connectionId,
        'conn_demo_001',
      );
      expect(harness.scopes.current, same(selectedBefore));
      expect(harness.scopes.generation, generationBefore);

      await _close(tester, harness);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('combined overview never treats hidden balances as readable', (
    tester,
  ) async {
    final harness = _Harness(
      connections: [_connection('conn_demo_001', 'OKX', 'A account')],
    );
    await _pumpPortfolio(tester, harness, hidden: true);
    await tester.tap(find.byKey(const Key('toggle-combined-overview')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('overview-connection-conn_demo_001')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('overview-product-conn_demo_001-SPOT')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('•••••• USDT'), findsWidgets);
    expect(find.textContaining('100.00'), findsNothing);
    expect(find.textContaining('102.00'), findsNothing);
    expect(find.byKey(const Key('prepared-action-confirm')), findsNothing);
    await _close(tester, harness);
  });

  testWidgets('combined overview reports omitted connections at its cap', (
    tester,
  ) async {
    final connections = List.generate(
      9,
      (index) => _connection('conn_cap_$index', 'OKX', 'Account $index'),
    );
    final harness = _Harness(connections: connections);
    await _pumpPortfolio(tester, harness);
    await tester.tap(find.byKey(const Key('toggle-combined-overview')));
    await tester.pumpAndSettle();

    expect(
      find.text('Kết nối được xét 8/9 · Trang số dư đã yêu cầu 32.'),
      findsOneWidget,
    );
    expect(
      find.text('1 kết nối chưa được xét do giới hạn mỗi lần tải.'),
      findsOneWidget,
    );
    expect(harness.api.overviewRequests, hasLength(32));
    expect(
      harness.api.overviewRequests
          .map((request) => request.scope.connectionId)
          .toSet(),
      hasLength(8),
    );
    expect(
      harness.api.overviewRequests.every((request) => request.limit == 100),
      isTrue,
    );
    await _close(tester, harness);
  });

  testWidgets(
    'actual portfolio shell context strip follows owner and fits mobile and desktop',
    (tester) async {
      await tester.runAsync(_loadQaFonts);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      final harness = _Harness(position: _position());
      const boundaryKey = ValueKey('qa-selected-context-strip');
      var textScale = 2.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionStoreProvider.overrideWith((ref) => harness.sessions),
            connectionScopeStoreProvider.overrideWith((ref) => harness.scopes),
            selectedConnectionProvider.overrideWith((ref) => harness.selected),
            multiUserApiClientProvider.overrideWith((ref) => harness.api),
            isDarkModeProvider.overrideWith((ref) => false),
            navigationPreferencesInitialProvider.overrideWithValue(
              NavigationPreferences.defaults,
            ),
          ],
          child: MaterialApp(
            theme: _qaTheme(AppTheme.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(
                key: boundaryKey,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: const MainNavigationShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('A account · OKX SWAP'), findsOneWidget);
      expect(find.textContaining('demo global'), findsOneWidget);
      expect(
        find.byKey(const Key('change-connection-context')),
        findsOneWidget,
      );
      expect(
        tester
            .getRect(find.byKey(const Key('change-connection-context')))
            .height,
        greaterThanOrEqualTo(48),
      );
      await _saveQaPng(
        tester,
        boundaryKey,
        'account-context-portfolio-360-light-text-2.0x.png',
      );

      textScale = 1.0;
      tester.view.physicalSize = const Size(1440, 1000);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionStoreProvider.overrideWith((ref) => harness.sessions),
            connectionScopeStoreProvider.overrideWith((ref) => harness.scopes),
            selectedConnectionProvider.overrideWith((ref) => harness.selected),
            multiUserApiClientProvider.overrideWith((ref) => harness.api),
            isDarkModeProvider.overrideWith((ref) => false),
            navigationPreferencesInitialProvider.overrideWithValue(
              NavigationPreferences.defaults,
            ),
          ],
          child: MaterialApp(
            theme: _qaTheme(AppTheme.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(
                key: boundaryKey,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: const MainNavigationShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _saveQaPng(
        tester,
        boundaryKey,
        'account-context-portfolio-1440-light-text-1.0x.png',
      );

      final replacement = UserSession(
        userId: 'user-b',
        username: 'bob',
        sessionId: 'session-b',
        mode: 'ordinary',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        bearerToken: 'opaque-b',
      );
      harness.sessions.update(replacement);
      harness.scopes.clear();
      harness.selected.clear();
      await tester.pumpAndSettle();
      expect(find.textContaining('A account'), findsNothing);
      await _close(tester, harness);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('renders responsive T114 QA matrix and critical states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.runAsync(_loadQaFonts);
    final output = Directory('/private/tmp/t114-resume-qa');
    await tester.runAsync(() => output.create(recursive: true));

    for (final width in [360, 768, 1440]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final textScale in [1.0, 2.0]) {
          final name = 'portfolio-${width}-${mode.name}-text-${textScale}x';
          final harness = _Harness(position: _position());
          final boundaryKey = ValueKey('qa-render-$name');
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width.toDouble(), 900);
          await _pumpQaScreen(
            tester,
            harness,
            screen: const MultiUserPortfolioScreen(),
            mode: mode,
            textScale: textScale,
            boundaryKey: boundaryKey,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
          await _saveQaPng(tester, boundaryKey, '$name.png');
          if (width == 360 && mode == ThemeMode.light && textScale == 2.0) {
            await tester.scrollUntilVisible(
              find.text('USDT'),
              80,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.text('Khả dụng 100.00 USDT'), findsOneWidget);
            expect(find.text('Khóa 2 USDT'), findsOneWidget);
            expect(find.text('Tổng 102.00 USDT'), findsOneWidget);
            final balanceCard = find
                .ancestor(of: find.text('USDT'), matching: find.byType(Card))
                .first;
            final cardRect = tester.getRect(balanceCard);
            expect(cardRect.height, greaterThan(0));
            expect(cardRect.bottom, lessThan(840));
            await _saveQaPng(
              tester,
              boundaryKey,
              'portfolio-360-light-text-2.0x-scrolled-balance.png',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          harness.dispose();
        }
      }
    }

    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    final actionHarness = _Harness(
      order: const NormalizedOrder(
        exchange: 'OKX',
        product: 'SWAP',
        environment: 'demo',
        region: 'global',
        orderId: 'order-native-77',
        instrument: 'BTC-USDT-SWAP',
        side: 'buy',
        orderType: 'limit',
        status: 'partially_filled',
        nativeQuantity: '5',
        quantityUnit: 'contracts',
        averagePrice: '320',
        limitPrice: '321.5',
        filledQuantity: '2',
        eventTime: null,
        nativeAsset: 'BTC',
        filledQuantityUnit: 'contracts',
        clientOrderId: 'client-a-1',
        metadataVersion: 'orders-v4',
      ),
    );
    final actionKey = const ValueKey('qa-action-confirmation');
    await _pumpQaScreen(
      tester,
      actionHarness,
      screen: const MultiUserOrdersScreen(),
      mode: ThemeMode.light,
      textScale: 1,
      boundaryKey: actionKey,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lệnh'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-order-order-native-77-0')));
    await tester.pumpAndSettle();
    final confirmationButton = find.byKey(const Key('prepared-action-confirm'));
    expect(tester.getRect(confirmationButton).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .getSemantics(confirmationButton)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await _saveQaPng(tester, actionKey, 'action-confirmation-360.png');
    await tester.pumpWidget(const SizedBox.shrink());
    actionHarness.dispose();

    final staleHarness = _Harness(position: _position(), complete: false);
    final staleKey = const ValueKey('qa-stale-metadata');
    await _pumpQaScreen(
      tester,
      staleHarness,
      screen: const MultiUserOrdersScreen(),
      mode: ThemeMode.dark,
      textScale: 1,
      boundaryKey: staleKey,
    );
    await tester.pumpAndSettle();
    await _saveQaPng(tester, staleKey, 'stale-metadata-360-dark.png');
    await tester.pumpWidget(const SizedBox.shrink());
    staleHarness.dispose();

    final pendingHarness = _Harness(position: _position());
    pendingHarness.pending.add(
      PendingOperation(
        scope: pendingHarness.scope,
        operationId: 'operation_0001',
        action: 'close_position',
        createdAt: DateTime.now().toUtc(),
        connectionLabel: 'A account',
        status: 'UNKNOWN',
        targets: const [
          {'index': 0, 'status': 'ATTEMPT_STARTED', 'result': null},
        ],
      ),
    );
    final pendingKey = const ValueKey('qa-pending-proof');
    await _pumpQaScreen(
      tester,
      pendingHarness,
      screen: const MultiUserOrdersScreen(),
      mode: ThemeMode.dark,
      textScale: 1,
      boundaryKey: pendingKey,
    );
    await tester.pumpAndSettle();
    await _saveQaPng(tester, pendingKey, 'pending-target-proof-768-dark.png');
    await tester.pumpWidget(const SizedBox.shrink());
    pendingHarness.dispose();

    final session = _session();
    final sessions = UserSessionStore(initialSession: session);
    final scopes = ConnectionScopeStore()
      ..select(
        session: session,
        connectionId: 'conn_binance_001',
        exchange: 'BINANCE',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      );
    const unavailableKey = ValueKey('qa-binance-unavailable');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionStoreProvider.overrideWith((ref) => sessions),
          connectionScopeStoreProvider.overrideWith((ref) => scopes),
        ],
        child: MaterialApp(
          theme: _qaTheme(AppTheme.light),
          darkTheme: _qaTheme(AppTheme.dark),
          themeMode: ThemeMode.dark,
          builder: (context, child) => RepaintBoundary(
            key: unavailableKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const MultiUserPublicPanelBoundary(
            feed: 'Bảng giá OKX SPOT',
            supportedProducts: {'SPOT'},
            child: Text('quote fixture must stay hidden'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('quote fixture must stay hidden'), findsNothing);
    await _saveQaPng(
      tester,
      unavailableKey,
      'binance-unavailable-360-dark.png',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    scopes.dispose();
    semantics.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpOrders(
  WidgetTester tester,
  _Harness harness, {
  bool useProviderPendingStore = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userSessionStoreProvider.overrideWith((ref) => harness.sessions),
        connectionScopeStoreProvider.overrideWith((ref) => harness.scopes),
        selectedConnectionProvider.overrideWith((ref) => harness.selected),
        if (!useProviderPendingStore)
          pendingOperationStoreProvider.overrideWith((ref) => harness.pending),
        multiUserApiClientProvider.overrideWith((ref) => harness.api),
      ],
      child: const MaterialApp(home: MultiUserOrdersScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPortfolio(
  WidgetTester tester,
  _Harness harness, {
  bool hidden = false,
  ForegroundReadGate? readGate,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userSessionStoreProvider.overrideWith((ref) => harness.sessions),
        connectionScopeStoreProvider.overrideWith((ref) => harness.scopes),
        selectedConnectionProvider.overrideWith((ref) => harness.selected),
        pendingOperationStoreProvider.overrideWith((ref) => harness.pending),
        multiUserApiClientProvider.overrideWith((ref) => harness.api),
        if (readGate != null)
          multiUserForegroundReadGateProvider.overrideWith((ref) {
            ref.onDispose(readGate.dispose);
            return readGate;
          }),
        hideBalanceProvider.overrideWith((ref) => hidden),
      ],
      child: const MaterialApp(home: MultiUserPortfolioScreen()),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _pumpQaScreen(
  WidgetTester tester,
  _Harness harness, {
  required Widget screen,
  required ThemeMode mode,
  required double textScale,
  required Key boundaryKey,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userSessionStoreProvider.overrideWith((ref) => harness.sessions),
        connectionScopeStoreProvider.overrideWith((ref) => harness.scopes),
        selectedConnectionProvider.overrideWith((ref) => harness.selected),
        pendingOperationStoreProvider.overrideWith((ref) => harness.pending),
        multiUserApiClientProvider.overrideWith((ref) => harness.api),
      ],
      child: MaterialApp(
        theme: _qaTheme(AppTheme.light),
        darkTheme: _qaTheme(AppTheme.dark),
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(
            key: boundaryKey,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: screen,
      ),
    ),
  );
}

ThemeData _qaTheme(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
  primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
);

Future<void> _saveQaPng(
  WidgetTester tester,
  Key boundaryKey,
  String filename,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  expect(image, isNotNull);
  final captured = image!;
  final data = await tester.runAsync(
    () => captured.toByteData(format: ui.ImageByteFormat.png),
  );
  captured.dispose();
  expect(data, isNotNull);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  await tester.runAsync(() async {
    const directory = '/private/tmp/t114-resume-qa';
    await Directory(directory).create(recursive: true);
    await File('$directory/$filename').writeAsBytes(bytes, flush: true);
  });
}

Future<void> _loadQaFonts() async {
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  while (directory.path != directory.parent.path) {
    final candidate = Directory(
      '${directory.path}${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
      'material_fonts',
    );
    if (await candidate.exists()) {
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final fontFile = File(
          '${candidate.path}${Platform.pathSeparator}${font.value}',
        );
        if (!await fontFile.exists()) continue;
        final bytes = await fontFile.readAsBytes();
        final loader = FontLoader(font.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
      return;
    }
    directory = directory.parent;
  }
  throw StateError('Flutter SDK material fonts not found for visual QA.');
}

Future<void> _close(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  harness.dispose();
}

NormalizedPosition _position({
  String product = 'SWAP',
  String instrument = 'BTC-USDT-SWAP',
  String? marginCurrency = 'USDT',
  String? positionId = 'position-1',
  String? quantityUnit = 'contracts',
  String nativeQuantity = '3',
  String? nativeAsset = 'USDT',
  String? side = 'long',
}) => NormalizedPosition(
  exchange: 'OKX',
  product: product,
  environment: 'demo',
  region: 'global',
  instrument: instrument,
  nativeQuantity: nativeQuantity,
  quantityUnit: quantityUnit,
  baseQuantity: '0.03',
  marginMode: 'cross',
  marginCurrency: marginCurrency,
  positionId: positionId,
  nativeAsset: nativeAsset,
  contractValue: '0.01',
  contractValueUnit: 'BTC',
  contractType: 'linear',
  settlementAsset: 'USDT',
  metadataVersion: 'contracts-v4',
  side: side,
  positionMode: 'long_short_mode',
  entryPrice: '32000',
  markPrice: '32100',
  unrealizedPnl: '3.00',
);

class _Harness {
  _Harness({
    List<NormalizedPosition>? positions,
    NormalizedPosition? position,
    NormalizedOrder? order,
    List<ConnectionRecord>? connections,
    this.complete = true,
    String selectedProduct = 'SWAP',
  }) : sessions = UserSessionStore(initialSession: _session()),
       scopes = ConnectionScopeStore(),
       selected = SelectedConnectionStore(),
       pending = PendingOperationStore() {
    scope = scopes.select(
      session: sessions.current!,
      connectionId: 'conn_demo_001',
      exchange: 'OKX',
      environment: 'demo',
      region: 'global',
      product: selectedProduct,
      credentialVersion: 1,
      permissionVersion: 1,
    )!;
    selected.select(
      const ConnectionRecord(
        connectionId: 'conn_demo_001',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        capabilities: ['read', 'trade'],
        nickname: 'A account',
        status: 'ACTIVE',
        credentialVersion: 1,
        permissionVersion: 1,
      ),
    );
    api = _FixtureApi(
      sessions: sessions,
      scopes: scopes,
      positionRows: positions ?? [if (position != null) position],
      order: order,
      complete: complete,
      connections:
          connections ?? [_connection('conn_demo_001', 'OKX', 'A account')],
    );
  }

  final UserSessionStore sessions;
  final ConnectionScopeStore scopes;
  final SelectedConnectionStore selected;
  final PendingOperationStore pending;
  late final ConnectionScope scope;
  late final _FixtureApi api;
  final bool complete;

  void dispose() {
    api.backend.close(force: true);
  }
}

class _FixtureApi extends MultiUserApiClient
    implements ReadOnlyBalanceScopeReader {
  _FixtureApi({
    required UserSessionStore sessions,
    required ConnectionScopeStore scopes,
    required this.positionRows,
    required this.order,
    required this.complete,
    required this.connections,
    List<_OverviewRequest>? sharedOverviewRequests,
    Set<String>? overviewNextCursorFor,
    Set<String>? overviewStaleFor,
    Set<String>? overviewUnavailableFor,
  }) : overviewRequests = sharedOverviewRequests ?? [],
       overviewNextCursorFor = overviewNextCursorFor ?? {},
       overviewStaleFor = overviewStaleFor ?? {},
       overviewUnavailableFor = overviewUnavailableFor ?? {},
       super(
         backend: BackendDataClient(
           baseUrl: 'https://fixture.example/gateway',
           isWeb: false,
         ),
         sessions: sessions,
         scopes: scopes,
         isWeb: false,
       );

  final List<NormalizedPosition> positionRows;
  final NormalizedOrder? order;
  final bool complete;
  final List<ConnectionRecord> connections;
  int balanceCalls = 0;
  int positionCalls = 0;
  int orderCalls = 0;
  int transientPositionFailuresRemaining = 0;
  final List<CancelToken> positionCancelTokens = [];
  Completer<void>? positionGate;
  Completer<void>? positionRequestStarted;
  Completer<void>? executeGate;
  Completer<void>? executeRequestStarted;
  Completer<void>? executeRequestReturned;
  bool executeThrows = false;
  int executeCalls = 0;
  int operationResultCalls = 0;
  int stepUpCalls = 0;
  int createConnectionCalls = 0;
  int prepareCalls = 0;
  String? lastAction;
  Map<String, String>? lastTargetIdentity;
  String resultStatus = 'UNKNOWN';
  final List<_OverviewRequest> overviewRequests;
  final Set<String> overviewNextCursorFor;
  final Set<String> overviewStaleFor;
  final Set<String> overviewUnavailableFor;
  String? overviewBlockedFor;
  String? overviewThrowsFor;
  Completer<void>? overviewGate;
  Completer<void>? overviewRequestStarted;
  Completer<void>? overviewRequestReturned;

  @override
  ReadOnlyBalanceScopeReader createReadOnlyScopeReader(
    ConnectionScopeStore isolatedScopes, {
    required UserSessionStore isolatedSessions,
  }) {
    final reader =
        _FixtureApi(
            sessions: isolatedSessions,
            scopes: isolatedScopes,
            positionRows: positionRows,
            order: order,
            complete: complete,
            connections: connections,
            sharedOverviewRequests: overviewRequests,
            overviewNextCursorFor: overviewNextCursorFor,
            overviewStaleFor: overviewStaleFor,
            overviewUnavailableFor: overviewUnavailableFor,
          )
          ..overviewBlockedFor = overviewBlockedFor
          ..overviewThrowsFor = overviewThrowsFor
          ..overviewGate = overviewGate
          ..overviewRequestStarted = overviewRequestStarted
          ..overviewRequestReturned = overviewRequestReturned;
    return reader;
  }

  @override
  Future<List<ConnectionRecord>> getConnections({
    CancelToken? cancelToken,
  }) async => connections;

  @override
  Future<DateTime> stepUp({
    required String password,
    required String totp,
  }) async {
    stepUpCalls++;
    return DateTime.now().add(const Duration(minutes: 5));
  }

  @override
  Future<ConnectionRecord> createConnection({
    required String exchange,
    required String environment,
    required String region,
    required String nickname,
    required String apiKey,
    required String apiSecret,
    String? passphrase,
  }) async {
    createConnectionCalls++;
    return connections.first;
  }

  @override
  Future<ScopedPage<NormalizedBalance>> balances(
    ConnectionScope scope, {
    String? cursor,
    int limit = 100,
    CancelToken? cancelToken,
  }) async {
    overviewRequests.add(_OverviewRequest(scope, limit));
    final key = '${scope.connectionId}:${scope.product}';
    if (key == overviewBlockedFor) {
      if (!(overviewRequestStarted?.isCompleted ?? true)) {
        overviewRequestStarted!.complete();
      }
      await overviewGate!.future;
      if (!(overviewRequestReturned?.isCompleted ?? true)) {
        overviewRequestReturned!.complete();
      }
      if (key == overviewThrowsFor) {
        throw StateError('Delayed fixture failure after projection disposal.');
      }
    }
    if (overviewUnavailableFor.contains(key)) {
      throw const BackendDataException(
        code: 'upstream_unavailable',
        message: 'Dữ liệu sàn tạm thời không khả dụng.',
        statusCode: 503,
      );
    }
    final now = DateTime.now().toUtc();
    final stale = overviewStaleFor.contains(key);
    final row = NormalizedBalance(
      exchange: scope.exchange,
      product: scope.product,
      environment: scope.environment,
      region: scope.region,
      asset: scope.exchange == 'BINANCE' ? 'BNB' : 'USDT',
      available: '100.00',
      locked: '2.00',
      total: '102.00',
      unit: scope.exchange == 'BINANCE' ? 'BNB' : 'USDT',
    );
    return ScopedPage(
      scope: scope,
      page: NormalizedPage(
        rows: [row],
        nextCursor: overviewNextCursorFor.contains(key) ? 'next-page' : null,
        meta: DataMeta(
          fetchedAt: now,
          asOf: now,
          snapshotExpiresAt: now.add(const Duration(minutes: 5)),
          stale: stale,
          complete: !stale,
        ),
      ),
    );
  }

  @override
  Future<ScopedPage<NormalizedBalance>> allBalances(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) async {
    balanceCalls++;
    return _page(
      scope,
      List.generate(
        500,
        (index) => NormalizedBalance(
          exchange: scope.exchange,
          product: scope.product,
          environment: scope.environment,
          region: scope.region,
          asset: index == 0 ? 'USDT' : 'ASSET-$index',
          available: index == 0 ? '100.00' : '1',
          locked: '2',
          total: index == 0 ? '102.00' : '3',
          unit: index == 0 ? 'USDT' : 'ASSET-$index',
        ),
      ),
    );
  }

  @override
  Future<ScopedPage<NormalizedPosition>> allPositions(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) async {
    positionCalls++;
    if (cancelToken != null) positionCancelTokens.add(cancelToken);
    if (positionCalls == 1 && positionGate != null) {
      if (!(positionRequestStarted?.isCompleted ?? true)) {
        positionRequestStarted!.complete();
      }
      await Future.any<void>([
        positionGate!.future,
        if (cancelToken != null) cancelToken.whenCancel.then<void>((_) {}),
      ]);
      if (cancelToken?.isCancelled == true) {
        throw const BackendDataException(
          code: 'request_cancelled',
          message: 'Foreground position read was canceled.',
        );
      }
    }
    if (transientPositionFailuresRemaining > 0) {
      transientPositionFailuresRemaining--;
      throw const BackendDataException(
        code: 'network_error',
        message: 'Fixture network interruption.',
        statusCode: 503,
      );
    }
    return _page(scope, positionRows);
  }

  @override
  Future<ScopedPage<NormalizedOrder>> allOrders(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) async {
    orderCalls++;
    return _page(scope, [if (order != null) order!]);
  }

  @override
  Future<Map<String, dynamic>> prepareAction(
    ConnectionScope scope, {
    required String action,
    required Map<String, String> targetIdentity,
  }) async {
    prepareCalls++;
    lastAction = action;
    lastTargetIdentity = Map.of(targetIdentity);
    final summary = <String, Object?>{
      'action': action,
      'identity': targetIdentity,
      if (action == 'close_position') ...{
        'direction': 'long',
        'currentSize': '3',
      } else ...{
        'price': targetIdentity['px'],
        'originalSize': targetIdentity['sz'],
        'filledSize': '2',
        'remainingSize': '3',
      },
    };
    return {
      'operationId': 'operation_0001',
      'connectionId': scope.connectionId,
      'product': scope.product,
      'action': action,
      'status': 'PREPARED',
      'confirmationToken': 'fixture-confirmation-token',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 2))
          .toIso8601String(),
      'targets': [
        {'index': 0, 'status': 'PREPARED', 'result': null},
      ],
      'summary': summary,
    };
  }

  @override
  Future<Map<String, dynamic>> executeAction(
    ConnectionScope scope, {
    required String action,
    required String operationId,
    required String confirmationToken,
    required String idempotencyKey,
  }) async {
    executeCalls++;
    if (!(executeRequestStarted?.isCompleted ?? true)) {
      executeRequestStarted!.complete();
    }
    if (executeGate != null) await executeGate!.future;
    if (executeThrows) {
      if (!(executeRequestReturned?.isCompleted ?? true)) {
        executeRequestReturned!.complete();
      }
      throw StateError('Fixture transport closed before receipt.');
    }
    final result = _operation(
      scope,
      operationId,
      action,
      'SENDING',
      'ATTEMPT_STARTED',
      {'positionVerified': false},
    );
    if (!(executeRequestReturned?.isCompleted ?? true)) {
      executeRequestReturned!.complete();
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> operationResult(
    ConnectionScope originalScope,
    String operationId,
    String action,
  ) async {
    operationResultCalls++;
    return _operation(
      originalScope,
      operationId,
      action,
      resultStatus,
      'PARTIAL',
      {'reason': 'partial outcome', 'positionVerified': false},
    );
  }

  Map<String, dynamic> _operation(
    ConnectionScope scope,
    String operationId,
    String action,
    String status,
    String targetStatus,
    Map<String, dynamic> result,
  ) => {
    'operationId': operationId,
    'connectionId': scope.connectionId,
    'product': scope.product,
    'action': action,
    'status': status,
    'targets': [
      {'index': 0, 'status': targetStatus, 'result': result},
    ],
  };

  ScopedPage<T> _page<T>(ConnectionScope scope, List<T> rows) {
    final now = DateTime.now().toUtc();
    return ScopedPage(
      scope: scope,
      page: NormalizedPage(
        rows: rows,
        nextCursor: null,
        meta: DataMeta(
          fetchedAt: now,
          asOf: now,
          snapshotExpiresAt: now.add(const Duration(minutes: 5)),
          stale: false,
          complete: complete,
        ),
      ),
    );
  }
}

UserSession _session() => UserSession(
  userId: 'user-a',
  username: 'alice',
  sessionId: 'session-a',
  mode: 'ordinary',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  stepUpUntil: DateTime.now().add(const Duration(minutes: 5)),
  bearerToken: 'opaque-a',
);

ConnectionRecord _connection(String id, String exchange, String nickname) =>
    ConnectionRecord(
      connectionId: id,
      exchange: exchange,
      environment: 'demo',
      region: 'global',
      capabilities: const ['read'],
      nickname: nickname,
      status: 'ACTIVE',
      credentialVersion: 1,
      permissionVersion: 1,
    );

class _OverviewRequest {
  const _OverviewRequest(this.scope, this.limit);

  final ConnectionScope scope;
  final int limit;
}

class _OverviewBoundaryAdapter implements HttpClientAdapter {
  _OverviewBoundaryAdapter({
    this.unauthorizedConnectionId,
    this.holdUnauthorizedResponse = false,
  });

  final String? unauthorizedConnectionId;
  final bool holdUnauthorizedResponse;
  final Completer<void> unauthorizedRequestStarted = Completer<void>();
  final Completer<void> _unauthorizedResponseGate = Completer<void>();
  final List<String> paths = [];
  final List<String> methods = [];
  final List<String> balanceConnectionIds = [];

  void releaseUnauthorizedResponse() {
    if (!_unauthorizedResponseGate.isCompleted) {
      _unauthorizedResponseGate.complete();
    }
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/gateway', '');
    paths.add(path);
    methods.add(options.method);
    final headers = {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };
    if (path == '/v2/connections') {
      return ResponseBody.fromString(
        jsonEncode({
          'connections': [
            {
              'connectionId': 'conn_demo_001',
              'exchange': 'OKX',
              'environment': 'demo',
              'region': 'global',
              'capabilities': ['read', 'trade'],
              'nickname': 'A account',
              'status': 'ACTIVE',
              'credentialVersion': 1,
              'permissionVersion': 1,
            },
            {
              'connectionId': 'conn_demo_002',
              'exchange': 'BINANCE',
              'environment': 'demo',
              'region': 'global',
              'capabilities': ['read'],
              'nickname': 'B account',
              'status': 'ACTIVE',
              'credentialVersion': 1,
              'permissionVersion': 1,
            },
          ],
        }),
        200,
        headers: headers,
      );
    }
    final match = RegExp(
      r'^/v2/connections/([A-Za-z0-9_-]+)/balances$',
    ).firstMatch(path);
    if (match != null) {
      final connectionId = match.group(1)!;
      balanceConnectionIds.add(connectionId);
      if (connectionId == unauthorizedConnectionId) {
        unauthorizedRequestStarted.complete();
        if (holdUnauthorizedResponse) await _unauthorizedResponseGate.future;
        return ResponseBody.fromString(
          '{"error":"unauthorized"}',
          401,
          headers: headers,
        );
      }
      final product = options.queryParameters['product']! as String;
      final now = DateTime.now().toUtc();
      return ResponseBody.fromString(
        jsonEncode({
          'data': [
            {
              'exchange': connectionId == 'conn_demo_001' ? 'OKX' : 'BINANCE',
              'product': product,
              'environment': 'demo',
              'region': 'global',
              'asset': 'USDT',
              'available': '10.00',
              'locked': '1.00',
              'total': '11.00',
              'unit': 'USDT',
            },
          ],
          'page': {'nextCursor': null},
          'dataMeta': {
            'fetchedAt': now.toIso8601String(),
            'asOf': now.toIso8601String(),
            'snapshotExpiresAt': now
                .add(const Duration(minutes: 1))
                .toIso8601String(),
            'stale': false,
            'complete': true,
          },
        }),
        200,
        headers: headers,
      );
    }
    return ResponseBody.fromString('{}', 404, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}
