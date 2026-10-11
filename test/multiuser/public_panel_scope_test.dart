import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/core/session/connection_scope.dart';
import 'package:trading_balance_f/core/session/user_session.dart';
import 'package:trading_balance_f/features/connections/data/multi_user_api_client.dart';
import 'package:trading_balance_f/features/connections/domain/connection_models.dart';
import 'package:trading_balance_f/features/connections/presentation/private_data_screens.dart';
import 'package:trading_balance_f/features/connections/presentation/providers/multi_user_provider.dart';
import 'package:trading_balance_f/features/market/presentation/market_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart'
    show isDarkModeProvider;

void main() {
  testWidgets('Binance scope shows an explicit unavailable OKX feed state', (
    tester,
  ) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionStoreProvider.overrideWith((ref) => sessions),
          connectionScopeStoreProvider.overrideWith((ref) => scopes),
        ],
        child: const MaterialApp(
          home: MultiUserPublicPanelBoundary(
            feed: 'Bảng giá OKX SPOT',
            supportedProducts: {'SPOT'},
            child: Text('fixture OKX quote'),
          ),
        ),
      ),
    );

    expect(find.textContaining('chỉ được xác minh cho OKX'), findsOneWidget);
    expect(find.text('fixture OKX quote'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    scopes.dispose();
  });

  testWidgets('public feed subtree resets when OKX scope context changes', (
    tester,
  ) async {
    final session = _session();
    final sessions = UserSessionStore(initialSession: session);
    final scopes = ConnectionScopeStore()
      ..select(
        session: session,
        connectionId: 'conn_okx_001',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionStoreProvider.overrideWith((ref) => sessions),
          connectionScopeStoreProvider.overrideWith((ref) => scopes),
        ],
        child: const MaterialApp(
          home: MultiUserPublicPanelBoundary(
            feed: 'Market feed',
            supportedProducts: {'SPOT'},
            child: _Counter(),
          ),
        ),
      ),
    );
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('increment')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    scopes.select(
      session: session,
      connectionId: 'conn_okx_001',
      exchange: 'OKX',
      environment: 'production',
      region: 'global',
      product: 'SPOT',
      credentialVersion: 1,
      permissionVersion: 1,
    );
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    scopes.dispose();
  });

  testWidgets(
    'real MarketScreen key changes preserve root stores and next private read',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _session();
      final sessions = UserSessionStore(initialSession: session);
      final scopes = ConnectionScopeStore();
      scopes.select(
        session: session,
        connectionId: 'conn_okx_a',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      );
      final selected = SelectedConnectionStore()
        ..select(_connection('conn_okx_c', 'A third account'));
      final api = _PrivateReadApi(
        sessions: sessions,
        scopes: scopes,
        backend: BackendDataClient(
          baseUrl: 'https://fixture.example/gateway',
          isWeb: false,
        ),
      );
      final nextScopeFixture = ConnectionScope(
        userId: session.userId,
        sessionId: session.sessionId,
        connectionId: 'conn_okx_b',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
        generation: scopes.generation + 1,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionStoreProvider.overrideWith((ref) => sessions),
            connectionScopeStoreProvider.overrideWith((ref) => scopes),
            selectedConnectionProvider.overrideWith((ref) => selected),
            multiUserApiClientProvider.overrideWith((ref) => api),
            isDarkModeProvider.overrideWith((ref) => false),
            marketListProvider.overrideWith(
              (ref) async => const <MarketTicker>[],
            ),
            scopedMarketListProvider(
              const ConnectionScope(
                userId: 'user-a',
                sessionId: 'session-a',
                connectionId: 'conn_okx_a',
                exchange: 'OKX',
                environment: 'demo',
                region: 'global',
                product: 'SPOT',
                credentialVersion: 1,
                permissionVersion: 1,
                generation: 1,
              ),
            ).overrideWith((ref) async => const <MarketTicker>[]),
            scopedMarketListProvider(
              nextScopeFixture,
            ).overrideWith((ref) async => const <MarketTicker>[]),
          ],
          child: const MaterialApp(home: _DestinationSwitcher()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thị trường (Top 50)'), findsOneWidget);

      final nextScope = scopes.select(
        session: session,
        connectionId: 'conn_okx_b',
        exchange: 'OKX',
        environment: 'demo',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      );
      expect(nextScope, isNotNull);
      await tester.pumpAndSettle();

      expect(sessions.current, same(session));
      expect(scopes.current, same(nextScope));
      expect(scopes.matches(nextScope!.generation, nextScope), isTrue);
      expect(tester.takeException(), isNull);

      final selectedScope = scopes.select(
        session: session,
        connectionId: 'conn_okx_c',
        exchange: 'OKX',
        environment: 'production',
        region: 'global',
        product: 'SPOT',
        credentialVersion: 1,
        permissionVersion: 1,
      );
      expect(selectedScope, isNotNull);
      selected.select(_connection('conn_okx_c', 'A third account'));
      await tester.pumpAndSettle();
      expect(scopes.matches(selectedScope!.generation, selectedScope), isTrue);

      await tester.tap(find.byKey(const Key('open-private-portfolio')));
      await tester.pumpAndSettle();
      expect(find.byType(MultiUserPortfolioScreen), findsOneWidget);
      expect(api.positionReads, greaterThan(0));
      expect(api.orderReads, greaterThan(0));
      expect(sessions.current, same(session));
      expect(scopes.matches(selectedScope.generation, selectedScope), isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      api.backend.close(force: true);
      sessions.dispose();
      scopes.dispose();
      selected.dispose();
    },
  );
}

UserSession _session() => UserSession(
  userId: 'user-a',
  username: 'alice',
  sessionId: 'session-a',
  mode: 'ordinary',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  bearerToken: 'opaque-a',
);

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('increment'),
    onPressed: () => setState(() => value++),
    child: Text('$value'),
  );
}

class _DestinationSwitcher extends StatefulWidget {
  const _DestinationSwitcher();

  @override
  State<_DestinationSwitcher> createState() => _DestinationSwitcherState();
}

class _DestinationSwitcherState extends State<_DestinationSwitcher> {
  bool _showPrivate = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          key: const Key('open-private-portfolio'),
          onPressed: () => setState(() => _showPrivate = true),
          child: const Text('Open private portfolio'),
        ),
        Expanded(
          child: _showPrivate
              ? const MultiUserPortfolioScreen()
              : const MultiUserPublicPanelBoundary(
                  feed: 'Bảng giá OKX SPOT',
                  supportedProducts: {'SPOT'},
                  child: MarketScreen(),
                ),
        ),
      ],
    ),
  );
}

class _PrivateReadApi extends MultiUserApiClient {
  _PrivateReadApi({
    required super.sessions,
    required super.scopes,
    required super.backend,
  }) : super(isWeb: false);

  int positionReads = 0;
  int orderReads = 0;

  @override
  Future<ScopedPage<NormalizedPosition>> allPositions(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) async {
    positionReads++;
    return _emptyPage(scope, const <NormalizedPosition>[]);
  }

  @override
  Future<ScopedPage<NormalizedOrder>> allOrders(
    ConnectionScope scope, {
    CancelToken? cancelToken,
  }) async {
    orderReads++;
    return _emptyPage(scope, const <NormalizedOrder>[]);
  }
}

ScopedPage<T> _emptyPage<T>(ConnectionScope scope, List<T> rows) {
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
        complete: true,
      ),
    ),
  );
}

ConnectionRecord _connection(String id, String nickname) => ConnectionRecord(
  connectionId: id,
  exchange: 'OKX',
  environment: 'production',
  region: 'global',
  capabilities: const ['read', 'trade'],
  nickname: nickname,
  status: 'ACTIVE',
  credentialVersion: 1,
  permissionVersion: 1,
);
