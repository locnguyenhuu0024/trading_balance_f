import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/exchange/scoped_read.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/data/portfolio_repository.dart';
import '../../support/fake_exchange_adapter.dart';

final visibleAccount = FutureProvider.autoDispose<AccountSnapshot>((ref) {
  final scope = ref.watch(exchangeScopeProvider);
  return ref.watch(scopedAccountProvider(scope).future);
});

class TestStorage extends SecureStorageHelper {
  TestStorage() : super(const FlutterSecureStorage());
  @override
  Future<void> saveSelectedConnectionId(String id) async {}
}

class PendingPortfolio implements PortfolioRepository {
  final requests = <Completer<OkxAccountData>>[];
  final tokens = <CancelToken>[];
  @override
  Future<OkxAccountData> getAccountBalance({CancelToken? cancelToken}) {
    tokens.add(cancelToken!);
    final pending = Completer<OkxAccountData>();
    requests.add(pending);
    return pending.future;
  }
}

void main() {
  late PendingPortfolio pending;
  late FakeExchangeAdapter fake;
  late SecureStorageHelper storage;
  late ProviderContainer container;
  setUp(() {
    pending = PendingPortfolio();
    fake = FakeExchangeAdapter();
    storage = TestStorage();
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        portfolioRepositoryProvider.overrideWithValue(pending),
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            const ExchangeRegistration(
              profile: ConnectionProfile(
                connectionId: 'okx-default',
                exchange: ExchangeId.okx,
                label: 'OKX',
              ),
              adapter: OkxAdapter(),
            ),
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'fake',
                exchange: ExchangeId.binance,
                label: 'Fake',
              ),
              adapter: fake,
            ),
          ],
        ),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    storage.dispose();
  });

  test('late OKX response is dropped and cancelled on selection', () async {
    final sub = container.listen(
      visibleAccount,
      (_, __) {},
      fireImmediately: true,
    );
    await container.pump();
    expect(pending.tokens, hasLength(1));
    container.read(selectConnectionProvider)('fake');
    await container.pump();
    expect(pending.tokens.single.isCancelled, isTrue);
    pending.requests.single.complete(
      const OkxAccountData(
        details: [OkxCoinDetail(ccy: 'LATE', eq: '999')],
      ),
    );
    await container.pump();
    final result = await container.read(visibleAccount.future);
    expect(result.balances.single.asset, 'FAKE');
    expect(result.balances.single.total, '42');
    sub.close();
  });

  test('fake 429 does not close OKX lane', () async {
    final fakeCoordinator = container.read(
      exchangeRequestCoordinatorProvider(ExchangeId.binance),
    );
    final okx = container.read(
      exchangeRequestCoordinatorProvider(ExchangeId.okx),
    );
    final error = DioException(
      requestOptions: RequestOptions(path: '/fake'),
      response: Response(
        requestOptions: RequestOptions(path: '/fake'),
        statusCode: 429,
      ),
    );
    await expectLater(
      fakeCoordinator.run<void>(
        lane: RequestLane.authenticated,
        key: 'account',
        request: () async => throw error,
      ),
      throwsA(isA<RequestRateLimitException>()),
    );
    expect(fakeCoordinator.isBackingOff(RequestLane.authenticated), isTrue);
    expect(
      await okx.run(
        lane: RequestLane.authenticated,
        key: 'account',
        request: () async => 'ok',
      ),
      'ok',
    );
  });

  test('credential rotation cancels and drops an in-flight OKX read', () async {
    final sub = container.listen(
      visibleAccount,
      (_, __) {},
      fireImmediately: true,
    );
    await container.pump();
    final oldToken = pending.tokens.single;
    await storage.trackOkxCredentialMutation(() async {});
    await container.pump();
    expect(oldToken.isCancelled, isTrue);
    pending.requests.first.complete(
      const OkxAccountData(details: [OkxCoinDetail(ccy: 'OLD')]),
    );
    await container.pump();
    expect(container.read(exchangeScopeProvider).credentialGeneration, 2);
    expect(
      container
              .read(visibleAccount)
              .valueOrNull
              ?.balances
              .any((b) => b.asset == 'OLD') ??
          false,
      isFalse,
    );
    sub.close();
  });

  test('rapid switch back uses a new key and fresh read', () async {
    final sub = container.listen(
      visibleAccount,
      (_, __) {},
      fireImmediately: true,
    );
    await container.pump();
    final initial = container.read(exchangeScopeProvider);
    container.read(selectConnectionProvider)('fake');
    container.read(selectConnectionProvider)('okx-default');
    await container.pump();
    final current = container.read(exchangeScopeProvider);
    expect(current, isNot(initial));
    expect(current.switchEpoch, initial.switchEpoch + 2);
    expect(pending.tokens.first.isCancelled, isTrue);
    pending.requests.first.complete(const OkxAccountData());
    await container.pump();
    expect(pending.requests, hasLength(2));
    pending.requests.last.complete(
      const OkxAccountData(details: [OkxCoinDetail(ccy: 'NEW')]),
    );
    final result = await container.read(visibleAccount.future);
    expect(result.balances.single.asset, 'NEW');
    sub.close();
  });
}
