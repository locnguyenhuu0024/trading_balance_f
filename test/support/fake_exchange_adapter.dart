import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trading_balance_f/core/exchange/exchange_adapter.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/market_source.dart';

class FakeExchangeAdapter implements ExchangeAdapter {
  int accountReads = 0;
  @override
  List<String> get marketProducts => const [];
  @override
  MarketSource market(Ref ref) => throw UnimplementedError();
  @override
  ExchangeId get id => ExchangeId.binance;
  @override
  ExchangeCapabilities get capabilities => const ExchangeCapabilities();
  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async {
    accountReads++;
    return const AccountSnapshot(
      balances: [AssetBalance(wallet: 'fake', asset: 'FAKE', total: '42')],
    );
  }

  @override
  Future<List<ExchangeOrder>> readOrders(Ref ref, ExchangeScope scope) async =>
      [];
  @override
  Future<List<ExchangePosition>> readPositions(
    Ref ref,
    ExchangeScope scope,
  ) async => [];
  @override
  void invalidateAccount(void Function(ProviderOrFamily) invalidate) {}
  @override
  void invalidateOrders(void Function(ProviderOrFamily) invalidate) {}
  @override
  void invalidatePositions(void Function(ProviderOrFamily) invalidate) {}
  @override
  ExchangeFailure classify(Object error) =>
      const ExchangeFailure(ExchangeFailureKind.other);
}
