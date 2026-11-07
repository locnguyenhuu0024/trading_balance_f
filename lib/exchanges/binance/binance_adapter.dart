import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/exchange/exchange_adapter.dart';
import '../../core/exchange/exchange_models.dart';
import '../../core/exchange/exchange_scope.dart';
import '../../core/exchange/market_source.dart';
import '../../core/security/secure_storage_helper.dart';
import '../../features/orders/presentation/providers/order_provider.dart';
import 'binance_client.dart';
import 'binance_market.dart';
import 'binance_private_client.dart';
import 'binance_reader.dart';

final binanceIsWebProvider = Provider<bool>((ref) => kIsWeb);
final binancePrivateClientProvider = FutureProvider<BinancePrivateClient>((
  ref,
) async {
  final storage = ref.watch(secureStorageProvider);
  final snapshot = ref.watch(binanceCredentialReadScopeProvider).state.value;
  final coordinator = ref.watch(
    exchangeRequestCoordinatorProvider(ExchangeId.binance),
  );
  final isWeb = ref.watch(binanceIsWebProvider);
  final key = await storage.getBinanceApiKey();
  final secret = await storage.getBinanceApiSecret();
  if (snapshot.rotating || snapshot != storage.binanceCredentialState.value) {
    throw const BinancePrivateException(
      ExchangeFailure(ExchangeFailureKind.cancellation),
    );
  }
  if (key == null ||
      secret == null ||
      key.trim().isEmpty ||
      secret.trim().isEmpty) {
    throw const BinancePrivateException(
      ExchangeFailure(ExchangeFailureKind.credential),
    );
  }
  return BinancePrivateClient(
    keys: BinanceKeyBundle(apiKey: key, apiSecret: secret),
    credentialState: storage.binanceCredentialState,
    coordinator: coordinator,
    isWeb: isWeb,
  );
});
final binanceMarketProvider = Provider<BinanceMarket>(
  (ref) => BinanceMarket(ref.watch(binanceClientProvider)),
);
final binanceReaderProvider = FutureProvider<BinanceReader>((ref) async {
  final market = ref.watch(binanceMarketProvider);
  final client = await ref.watch(binancePrivateClientProvider.future);
  return BinanceReader(client, market);
});

class BinanceAdapter implements ExchangeAdapter {
  const BinanceAdapter();
  @override
  ExchangeId get id => ExchangeId.binance;
  @override
  List<String> get marketProducts => const ['SPOT', 'SWAP'];
  @override
  ExchangeCapabilities get capabilities =>
      const ExchangeCapabilities(readableProducts: ['SWAP', 'SPOT', 'MARGIN']);
  @override
  MarketSource market(Ref ref) => ref.watch(binanceMarketProvider);
  Future<BinanceReader> _reader(Ref ref, ExchangeScope scope) async {
    final reader = await ref.watch(binanceReaderProvider.future);
    if (reader.client.credentialState.value.generation !=
            scope.credentialGeneration ||
        reader.client.credentialState.value.rotating) {
      throw const BinancePrivateException(
        ExchangeFailure(ExchangeFailureKind.cancellation),
      );
    }
    return reader;
  }

  @override
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope) async =>
      (await _reader(ref, scope)).readAccount();
  @override
  Future<List<ExchangePosition>> readPositions(
    Ref ref,
    ExchangeScope scope,
  ) async => (await _reader(ref, scope)).readPositions();
  @override
  Future<List<ExchangeOrder>> readOrders(Ref ref, ExchangeScope scope) async {
    final filter = ref.watch(orderFilterProvider);
    return (await _reader(ref, scope)).readOrders(filter);
  }

  @override
  void invalidateAccount(void Function(ProviderOrFamily) invalidate) =>
      invalidate(binanceReaderProvider);
  @override
  void invalidatePositions(void Function(ProviderOrFamily) invalidate) =>
      invalidate(binanceReaderProvider);
  @override
  void invalidateOrders(void Function(ProviderOrFamily) invalidate) =>
      invalidate(binanceReaderProvider);
  @override
  ExchangeFailure classify(Object error) => error is BinancePrivateException
      ? error.failure
      : const ExchangeFailure(ExchangeFailureKind.other);
}
